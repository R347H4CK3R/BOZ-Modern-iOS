#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
extern void BOZDiagnosticLog(NSString *);
static Method OwnMethod(Class c, SEL sel) {
    unsigned count=0; Method found=NULL; Method *methods=class_copyMethodList(c,&count);
    for(unsigned i=0;i<count;i++) if(method_getName(methods[i])==sel){found=methods[i];break;}
    free(methods); return found;
}
__attribute__((constructor)) static void InstallBOZStartupTrace(void) {
    Class c=objc_getClass("s3eAppDelegate");
    if(!c){ BOZDiagnosticLog(@"trace=game-delegate-not-found"); return; }
    const char *names[]={"application:didFinishLaunchingWithOptions:","application:didFinishLaunchingInternal:"};
    for(unsigned i=0;i<2;i++){
        SEL sel=sel_registerName(names[i]); Method method=OwnMethod(c,sel);
        if(!method)continue;
        IMP original=method_getImplementation(method);
        NSString *label=[NSString stringWithUTF8String:names[i]];
        IMP replacement=imp_implementationWithBlock(^BOOL(id object,UIApplication *app,id options){
            BOZDiagnosticLog([label stringByAppendingString:@" enter"]);
            BOOL result=((BOOL(*)(id,SEL,id,id))original)(object,sel,app,options);
            BOZDiagnosticLog([label stringByAppendingString:@" return"]);
            return result;
        });
        method_setImplementation(method,replacement);
    }
    SEL active=@selector(applicationDidBecomeActive:);
    Method activeMethod=OwnMethod(c,active);
    if(activeMethod){
        IMP original=method_getImplementation(activeMethod);
        method_setImplementation(activeMethod,imp_implementationWithBlock(^(id object,UIApplication *app){
            BOZDiagnosticLog(@"game-activation enter");
            ((void(*)(id,SEL,id))original)(object,active,app);
            BOZDiagnosticLog(@"game-activation return");
        }));
    }
    const char *classes[]={"MainView","GLView"};
    const char *selectors[]={"layoutSubviews","show"};
    for(unsigned i=0;i<2;i++){
        Class cls=objc_getClass(classes[i]);SEL selector=sel_registerName(selectors[i]);
        Method method=OwnMethod(cls,selector);if(!method)continue;
        IMP original=method_getImplementation(method);
        NSString *label=[NSString stringWithFormat:@"%s.%s",classes[i],selectors[i]];
        __block BOOL first=YES;
        method_setImplementation(method,imp_implementationWithBlock(^(id object){
            BOOL log=first; first=NO;
            if(log)BOZDiagnosticLog([label stringByAppendingString:@" enter"]);
            ((void(*)(id,SEL))original)(object,selector);
            if(log)BOZDiagnosticLog([label stringByAppendingString:@" return"]);
        }));
    }
    BOZDiagnosticLog(@"trace=v2 hooks-installed");
}
