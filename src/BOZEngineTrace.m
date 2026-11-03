#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <pthread.h>
#import <signal.h>
#import <unistd.h>
#import <fcntl.h>
#import "fishhook.h"

extern void BOZDiagnosticLog(NSString *message);
typedef struct { void *(*start)(void *); void *argument; } BOZThreadContext;

static void *BOZThreadStart(void *raw) {
    BOZThreadContext context=*(BOZThreadContext *)raw;
    free(raw);
    @autoreleasepool {
        BOZDiagnosticLog([NSString stringWithFormat:@"engine-thread enter start=%p",context.start]);
        void *result=context.start(context.argument);
        BOZDiagnosticLog(@"engine-thread return");
        return result;
    }
}
static int BOZPthreadCreate(pthread_t *thread,const pthread_attr_t *attributes,
                           void *(*start)(void *),void *argument) {
    BOZDiagnosticLog([NSString stringWithFormat:@"pthread_create request start=%p caller=%p",start,__builtin_return_address(0)]);
    BOZThreadContext *context=malloc(sizeof(*context));
    if(!context)return pthread_create(thread,attributes,start,argument);
    context->start=start;context->argument=argument;
    int result=pthread_create(thread,attributes,BOZThreadStart,context);
    if(result)free(context);
    BOZDiagnosticLog([NSString stringWithFormat:@"pthread_create result=%d",result]);
    return result;
}
__attribute__((noreturn)) static void BOZExit(int code) {
    BOZDiagnosticLog([NSString stringWithFormat:@"termination=exit code=%d caller=%p",code,__builtin_return_address(0)]);
    exit(code);
}
__attribute__((noreturn)) static void BOZImmediateExit(int code) {
    BOZDiagnosticLog([NSString stringWithFormat:@"termination=_exit code=%d caller=%p",code,__builtin_return_address(0)]);
    _exit(code);
}
__attribute__((noreturn)) static void BOZAbort(void) {
    BOZDiagnosticLog([NSString stringWithFormat:@"termination=abort caller=%p",__builtin_return_address(0)]);
    abort();
}
__attribute__((noreturn)) static void BOZPthreadExit(void *result) {
    BOZDiagnosticLog([NSString stringWithFormat:@"termination=pthread_exit caller=%p",__builtin_return_address(0)]);
    pthread_exit(result);
}
static void (*BOZSignal(int number,void (*handler)(int)))(int) {
    BOZDiagnosticLog([NSString stringWithFormat:@"engine-signal-handler signal=%d handler=%p",number,handler]);
    return signal(number,handler);
}
static int BOZSigaction(int number,const struct sigaction *action,struct sigaction *previous) {
    if(action) BOZDiagnosticLog([NSString stringWithFormat:@"engine-sigaction signal=%d flags=%x",number,action->sa_flags]);
    return sigaction(number,action,previous);
}

__attribute__((constructor)) static void BOZInstallEngineTrace(void) {
    @autoreleasepool {
        // m_View is a game-owned accessor that our Objective-C tracing leaves untouched.
        Method method=class_getInstanceMethod(objc_getClass("s3eAppDelegate"),sel_registerName("m_View"));
        Dl_info info={0};
        if(!method || !dladdr((void *)method_getImplementation(method),&info) || !info.dli_fbase) {
            BOZDiagnosticLog(@"engine-trace=guest-image-unresolved");return;
        }
        const struct mach_header_64 *header=info.dli_fbase;
        if(header->magic!=MH_MAGIC_64)return;
        intptr_t slide=0; BOOL foundText=NO;
        const struct load_command *command=(const void *)(header+1);
        for(uint32_t i=0;i<header->ncmds;i++) {
            if(command->cmd==LC_SEGMENT_64) {
                const struct segment_command_64 *segment=(const void *)command;
                if(!strncmp(segment->segname,"__TEXT",16)) {
                    slide=(intptr_t)header-(intptr_t)segment->vmaddr;foundText=YES;break;
                }
            }
            command=(const void *)((const char *)command+command->cmdsize);
        }
        if(!foundText)return;
        struct rebinding bindings[]={
            {"pthread_create",BOZPthreadCreate,NULL},{"pthread_exit",BOZPthreadExit,NULL},
            {"exit",BOZExit,NULL},{"_exit",BOZImmediateExit,NULL},{"abort",BOZAbort,NULL},
            {"signal",BOZSignal,NULL},{"sigaction",BOZSigaction,NULL}
        };
        // Only the guest's import slots are changed. Wrapper calls still use the
        // original libc functions through this diagnostic image's own imports.
        int result=rebind_symbols_image((void *)header,slide,bindings,sizeof(bindings)/sizeof(bindings[0]));
        BOZDiagnosticLog([NSString stringWithFormat:@"engine-trace=v3 bind-result=%d game-base=%p",result,header]);
        NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        NSString *path=[docs stringByAppendingPathComponent:@"BOZDiagnostics/engine-console.log"];
        // Append across launches so an immediate exit cannot erase engine output.
        int fd=open(path.fileSystemRepresentation,O_CREAT|O_WRONLY|O_APPEND,0600);
        if(fd>=0) {
            dup2(fd,STDOUT_FILENO);dup2(fd,STDERR_FILENO);close(fd);
            setvbuf(stdout,NULL,_IONBF,0);setvbuf(stderr,NULL,_IONBF,0);
            BOZDiagnosticLog(@"engine-console=capture-enabled-local-only");
        }
    }
}
