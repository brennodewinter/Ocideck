// Test-only dylib, never bundled with OciDeck. Dispatch the actual Cmd+Q menu
// equivalent in AppKit, without Accessibility permission or a production hook.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *exit_path = NULL;
static void record_clean_exit(void) {
  if (!exit_path) return;
  FILE *file = fopen(exit_path, "w");
  if (file) { fputs("clean-exit\n", file); fclose(file); }
}

void ocideck_smoke_record_clean_exit(const char *path) {
  exit_path = strdup(path);
  atexit(record_clean_exit);
}

int ocideck_smoke_cmd_q(void) {
  __block int handled = 0;
  void (^send)(void) = ^{
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                    location:NSZeroPoint
                               modifierFlags:NSEventModifierFlagCommand
                                   timestamp:0
                                windowNumber:0
                                     context:nil
                                  characters:@"q"
                 charactersIgnoringModifiers:@"q"
                                   isARepeat:NO
                                     keyCode:12];
    handled = [NSApp.mainMenu performKeyEquivalent:event] ? 1 : 0;
  };
  if ([NSThread isMainThread]) send();
  else dispatch_sync(dispatch_get_main_queue(), send);
  return handled;
}
