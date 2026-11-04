"""Compile the real Frame callback with mocked presentation/input on macOS.

Regression: frames must dispatch commands even when no yield hook ever fires;
main-thread presentation and reentrant callbacks must not dispatch commands.
"""
import pathlib, subprocess, tempfile
source=pathlib.Path('src/BOZModernInput.m').read_text()
start=source.index('static void Frame(id self,SEL selector) {')
end=source.index('@interface BOZModernSurface',start)
frame=source[start:end]
prefix='''#import <Foundation/Foundation.h>
#include <pthread.h>
#include <stdatomic.h>
#include <assert.h>
#include <stdio.h>
static _Atomic(unsigned) EngineFrames;
static _Atomic(int) SawMainFrame,InsideFrame;
static int shows,ticks,presented;
static void Log(NSString *message) { (void)message; }
static void Show(id object,SEL selector) { (void)object;(void)selector;shows++;presented=1; }
static void (*OriginalShow)(id,SEL)=Show;
static void TickControls(void) { assert(!pthread_main_np());assert(presented);ticks++;presented=0; }
'''
suffix='''
static void *Worker(void *unused) {
    (void)unused;Frame(nil,NULL);Frame(nil,NULL);
    atomic_store(&InsideFrame,1);Frame(nil,NULL);atomic_store(&InsideFrame,0);
    return NULL;
}
int main(void) {
    Frame(nil,NULL);assert(shows==1&&ticks==0);
    pthread_t worker;assert(!pthread_create(&worker,NULL,Worker,NULL));assert(!pthread_join(worker,NULL));
    assert(shows==4&&ticks==2);assert(atomic_load(&EngineFrames)==3);assert(atomic_load(&SawMainFrame)==1);
    puts("PASS: actual Frame callback dispatches after presentation without yields, blocks UI-thread and reentrant dispatch");
    return 0;
}
'''
with tempfile.TemporaryDirectory() as folder:
    path=pathlib.Path(folder)/'frame.m';path.write_text(prefix+frame+suffix)
    binary=pathlib.Path(folder)/'frame-tests'
    subprocess.run(['clang','-fobjc-arc','-std=gnu11','-framework','Foundation',str(path),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)

