#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, CMOperation) {
    CMOperationNone,
    CMOperationStatus,
    CMOperationInstall,
    CMOperationStart,
    CMOperationStop,
    CMOperationRestart,
};

static NSImage *CMSymbol(NSString *name, NSString *description) {
    return [NSImage imageWithSystemSymbolName:name accessibilityDescription:description];
}

static NSTextField *CMLabel(NSString *text, NSFont *font, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 0;
    return label;
}

static NSStackView *CMHorizontalStack(NSArray<NSView *> *views, CGFloat spacing) {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    return stack;
}

static NSStackView *CMVerticalStack(NSArray<NSView *> *views, CGFloat spacing) {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = spacing;
    return stack;
}

@interface CMFlippedView : NSView
@end

@implementation CMFlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface CMSetupController : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSAlert *lifecycleAlert;
@property(nonatomic, copy) NSString *sourceFolder;
@property(nonatomic, strong) NSDictionary<NSString *, NSString *> *status;
@property(nonatomic, strong) NSTask *activeTask;
@property(nonatomic) CMOperation activeOperation;
@property(nonatomic) BOOL loadedConfiguration;
@property(nonatomic) BOOL cancelRequested;

@property(nonatomic, strong) NSTextField *statusBadge;
@property(nonatomic, strong) NSProgressIndicator *progressIndicator;
@property(nonatomic, strong) NSTextField *overviewTitle;
@property(nonatomic, strong) NSTextField *operationLabel;
@property(nonatomic, strong) NSTextField *sourceVersionLabel;
@property(nonatomic, strong) NSTextField *installedVersionLabel;
@property(nonatomic, strong) NSTextField *installPathLabel;
@property(nonatomic, strong) NSTextField *updateLabel;
@property(nonatomic, strong) NSTextField *errorLabel;
@property(nonatomic, strong) NSTextField *successLabel;

@property(nonatomic, strong) NSTextField *portField;
@property(nonatomic, strong) NSTextField *portHelpLabel;
@property(nonatomic, strong) NSSegmentedControl *sourceModeControl;
@property(nonatomic, strong) NSTextField *sourceModeDetail;
@property(nonatomic, strong) NSPopUpButton *locationPopup;
@property(nonatomic, strong) NSButton *shortcutCheckbox;
@property(nonatomic, strong) NSButton *openCheckbox;
@property(nonatomic, strong) NSTextField *runningApplyNote;

@property(nonatomic, strong) NSTextField *dashboardStatusLabel;
@property(nonatomic, strong) NSTextField *runnerStatusLabel;
@property(nonatomic, strong) NSButton *startButton;
@property(nonatomic, strong) NSButton *stopButton;
@property(nonatomic, strong) NSButton *restartButton;
@property(nonatomic, strong) NSButton *refreshButton;
@property(nonatomic, strong) NSButton *cancelButton;
@property(nonatomic, strong) NSButton *applyButton;
@end

@implementation CMSetupController

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSError *sourceError = nil;
    self.sourceFolder = [self locateSourceFolder:&sourceError];
    self.status = @{};
    [self buildWindow];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    if (self.sourceFolder.length == 0) {
        [self showError:sourceError.localizedDescription ?: @"Setup could not locate its Control Module folder."];
        self.operationLabel.stringValue = @"Setup cannot continue.";
        [self updateControls];
        return;
    }
    [self refreshStatusPreservingForm:NO];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    if (!self.window || self.sourceFolder.length == 0 || self.activeTask) return;
    [self refreshStatusPreservingForm:YES];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)hasVisibleWindows {
    (void)sender;
    if (!hasVisibleWindows && self.window) {
        [self.window makeKeyAndOrderFront:nil];
    }
    if (self.sourceFolder.length > 0 && !self.activeTask) {
        [self refreshStatusPreservingForm:YES];
    }
    return YES;
}

- (NSString *)locateSourceFolder:(NSError **)error {
    NSURL *appURL = NSBundle.mainBundle.bundleURL.URLByStandardizingPath;
    NSArray<NSURL *> *candidates = @[
        appURL.URLByDeletingLastPathComponent,
        appURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent,
    ];
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSURL *candidate in candidates) {
        NSString *package = [candidate URLByAppendingPathComponent:@"package.json"].path;
        NSString *installer = [candidate URLByAppendingPathComponent:@"support/mac/install.sh"].path;
        NSString *manager = [candidate URLByAppendingPathComponent:@"support/mac/manage.sh"].path;
        if ([files fileExistsAtPath:package]
            && [files isExecutableFileAtPath:installer]
            && [files isExecutableFileAtPath:manager]) {
            return candidate.path;
        }
    }
    if (error) {
        *error = [NSError errorWithDomain:@"ControlModuleSetup"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey:
                                     @"Setup could not verify its Control Module source folder. Keep Setup.app in the downloaded Control Module folder. No other folder was accessed."}];
    }
    return nil;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 820, 800);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"Control Module Setup";
    self.window.minSize = NSMakeSize(760, 700);
    self.window.delegate = self;
    [self.window center];

    NSView *root = self.window.contentView;

    NSView *header = [self buildHeader];
    NSView *footer = [self buildFooter];
    NSScrollView *scroll = [self buildContent];
    CGFloat width = NSWidth(root.bounds);
    CGFloat height = NSHeight(root.bounds);
    header.frame = NSMakeRect(0, height - 84, width, 84);
    header.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    footer.frame = NSMakeRect(0, 0, width, 64);
    footer.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    scroll.frame = NSMakeRect(0, 64, width, height - 148);
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:header];
    [root addSubview:scroll];
    [root addSubview:footer];
}

- (NSView *)buildHeader {
    NSView *container = [[NSView alloc] init];
    NSImageView *icon = [[NSImageView alloc] init];
    icon.image = CMSymbol(@"gearshape.2.fill", @"Control Module");
    icon.contentTintColor = NSColor.controlAccentColor;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:42],
        [icon.heightAnchor constraintEqualToConstant:42],
    ]];

    NSTextField *title = CMLabel(@"Control Module Setup", [NSFont systemFontOfSize:21 weight:NSFontWeightSemibold], NSColor.labelColor);
    NSTextField *subtitle = CMLabel(@"Install, update, and manage this local copy.", [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor);
    NSStackView *titles = CMVerticalStack(@[title, subtitle], 3);

    self.statusBadge = CMLabel(@"Checking", [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.secondaryLabelColor);
    self.statusBadge.alignment = NSTextAlignmentRight;
    self.progressIndicator = [[NSProgressIndicator alloc] init];
    self.progressIndicator.style = NSProgressIndicatorStyleSpinning;
    self.progressIndicator.controlSize = NSControlSizeSmall;
    self.progressIndicator.displayedWhenStopped = NO;
    [self.progressIndicator startAnimation:nil];
    NSStackView *status = CMHorizontalStack(@[self.progressIndicator, self.statusBadge], 7);

    NSStackView *row = CMHorizontalStack(@[icon, titles, [NSView new], status], 16);
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [[row.views objectAtIndex:2] setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [container addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:28],
        [row.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-28],
        [row.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
    ]];

    NSBox *line = [[NSBox alloc] init];
    line.boxType = NSBoxSeparator;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [line.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [line.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    return container;
}

- (NSScrollView *)buildContent {
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;

    NSView *document = [[CMFlippedView alloc] init];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *sections = CMVerticalStack(@[
        [self buildOverviewSection],
        [self buildConfigurationSection],
        [self buildServicesSection],
        [self buildMessages],
    ], 18);
    sections.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:sections];
    [NSLayoutConstraint activateConstraints:@[
        [sections.topAnchor constraintEqualToAnchor:document.topAnchor constant:20],
        [sections.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:28],
        [sections.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-28],
        [sections.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-20],
    ]];
    scroll.documentView = document;
    [NSLayoutConstraint activateConstraints:@[
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
    ]];
    return scroll;
}

- (NSBox *)sectionWithTitle:(NSString *)title content:(NSView *)content {
    NSBox *box = [[NSBox alloc] init];
    box.title = title;
    box.titleFont = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    box.boxType = NSBoxPrimary;
    box.contentViewMargins = NSMakeSize(18, 12);
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [box.contentView addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:box.contentView.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:box.contentView.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:box.contentView.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:box.contentView.bottomAnchor],
    ]];
    return box;
}

- (NSView *)buildOverviewSection {
    self.overviewTitle = CMLabel(@"Checking this copy", [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold], NSColor.labelColor);
    self.operationLabel = CMLabel(@"Reading this installation’s settings…", [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor);

    self.sourceVersionLabel = CMLabel(@"—", [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightMedium], NSColor.labelColor);
    self.installedVersionLabel = CMLabel(@"—", [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightMedium], NSColor.labelColor);
    self.installPathLabel = CMLabel(@"—", [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor);
    self.installPathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.installPathLabel.maximumNumberOfLines = 1;

    NSGridView *details = [NSGridView gridViewWithViews:@[
        @[CMLabel(@"Available source", [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor), self.sourceVersionLabel],
        @[CMLabel(@"Installed version", [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor), self.installedVersionLabel],
        @[CMLabel(@"Installed app", [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor), self.installPathLabel],
    ]];
    details.rowSpacing = 9;
    details.columnSpacing = 28;
    [details columnAtIndex:0].xPlacement = NSGridCellPlacementLeading;
    [details columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;

    self.updateLabel = CMLabel(@"", [NSFont systemFontOfSize:13 weight:NSFontWeightMedium], NSColor.controlAccentColor);
    self.updateLabel.hidden = YES;
    NSTextField *scope = CMLabel(
        @"Setup changes only this verified copy. Saved projects, logs, and settings remain in this installation’s private Application Support folder.",
        [NSFont systemFontOfSize:12],
        NSColor.secondaryLabelColor
    );
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    NSStackView *content = CMVerticalStack(@[
        self.overviewTitle,
        self.operationLabel,
        separator,
        details,
        self.updateLabel,
        scope,
    ], 11);
    return [self sectionWithTitle:@"Overview" content:content];
}

- (NSView *)buildConfigurationSection {
    self.portField = [[NSTextField alloc] init];
    self.portField.placeholderString = @"1025";
    self.portField.stringValue = @"1025";
    self.portField.alignment = NSTextAlignmentRight;
    self.portField.target = self;
    self.portField.action = @selector(portChanged:);
    [self.portField.widthAnchor constraintEqualToConstant:120].active = YES;
    self.portHelpLabel = CMLabel(@"", [NSFont systemFontOfSize:11], NSColor.systemRedColor);
    self.portHelpLabel.hidden = YES;
    NSStackView *portStack = CMVerticalStack(@[self.portField, self.portHelpLabel], 5);

    self.sourceModeControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Private working copy", @"Use downloaded folder"]
                                                                 trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                       target:self
                                                                       action:@selector(sourceModeChanged:)];
    self.sourceModeControl.selectedSegment = 0;
    self.sourceModeDetail = CMLabel(@"Runs from Application Support so opening Control Module does not need to read this folder.", [NSFont systemFontOfSize:11], NSColor.secondaryLabelColor);
    NSStackView *sourceModeStack = CMVerticalStack(@[self.sourceModeControl, self.sourceModeDetail], 6);

    self.locationPopup = [[NSPopUpButton alloc] init];
    [self.locationPopup addItemsWithTitles:@[@"Control Module folder", @"Personal Applications"]];
    [self.locationPopup.widthAnchor constraintEqualToConstant:230].active = YES;

    NSTextField *(^fieldLabel)(NSString *) = ^NSTextField *(NSString *text) {
        NSTextField *label = CMLabel(text, [NSFont systemFontOfSize:13], NSColor.labelColor);
        [label.widthAnchor constraintEqualToConstant:140].active = YES;
        return label;
    };
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[fieldLabel(@"Dashboard port"), portStack],
        @[fieldLabel(@"Source mode"), sourceModeStack],
        @[fieldLabel(@"Install app in"), self.locationPopup],
    ]];
    grid.rowSpacing = 16;
    grid.columnSpacing = 24;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementLeading;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;

    self.shortcutCheckbox = [NSButton checkboxWithTitle:@"Create a Desktop shortcut" target:nil action:nil];
    self.openCheckbox = [NSButton checkboxWithTitle:@"Open Control Module after applying" target:nil action:nil];
    self.openCheckbox.state = NSControlStateValueOn;
    self.runningApplyNote = CMLabel(
        @"Applying an update may briefly stop the dashboard and managed projects before reopening them safely.",
        [NSFont systemFontOfSize:11],
        NSColor.secondaryLabelColor
    );
    self.runningApplyNote.hidden = YES;
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    NSStackView *content = CMVerticalStack(@[
        grid,
        separator,
        self.shortcutCheckbox,
        self.openCheckbox,
        self.runningApplyNote,
    ], 12);
    return [self sectionWithTitle:@"Configuration" content:content];
}

- (NSButton *)actionButton:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.image = CMSymbol(symbol, title);
    button.imagePosition = NSImageLeading;
    return button;
}

- (NSView *)buildServicesSection {
    self.dashboardStatusLabel = CMLabel(@"●  Dashboard · 1025 — Stopped", [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor);
    self.runnerStatusLabel = CMLabel(@"●  Runner · 10001 — Stopped", [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor);
    NSStackView *serviceRow = CMHorizontalStack(@[self.dashboardStatusLabel, self.runnerStatusLabel, [NSView new]], 24);

    self.startButton = [self actionButton:@"Start" symbol:@"play.fill" action:@selector(startPressed:)];
    self.startButton.contentTintColor = NSColor.systemGreenColor;
    self.stopButton = [self actionButton:@"Stop" symbol:@"stop.fill" action:@selector(stopPressed:)];
    self.stopButton.contentTintColor = NSColor.systemRedColor;
    self.restartButton = [self actionButton:@"Restart" symbol:@"arrow.clockwise" action:@selector(restartPressed:)];
    self.refreshButton = [self actionButton:@"Refresh status" symbol:@"arrow.triangle.2.circlepath" action:@selector(refreshPressed:)];
    self.refreshButton.bezelStyle = NSBezelStyleInline;
    NSStackView *buttons = CMHorizontalStack(@[self.startButton, self.stopButton, self.restartButton, [NSView new], self.refreshButton], 10);
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    NSStackView *content = CMVerticalStack(@[serviceRow, separator, buttons], 13);
    return [self sectionWithTitle:@"Services" content:content];
}

- (NSView *)buildMessages {
    self.errorLabel = CMLabel(@"", [NSFont systemFontOfSize:13 weight:NSFontWeightMedium], NSColor.systemRedColor);
    self.successLabel = CMLabel(@"", [NSFont systemFontOfSize:13 weight:NSFontWeightMedium], NSColor.systemGreenColor);
    self.errorLabel.hidden = YES;
    self.successLabel.hidden = YES;
    return CMVerticalStack(@[self.errorLabel, self.successLabel], 8);
}

- (NSView *)buildFooter {
    NSView *container = [[NSView alloc] init];
    NSBox *line = [[NSBox alloc] init];
    line.boxType = NSBoxSeparator;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [line.topAnchor constraintEqualToAnchor:container.topAnchor],
        [line.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    ]];

    NSTextField *scope = CMLabel(@"Changes apply only to this verified Control Module copy.", [NSFont systemFontOfSize:11], NSColor.secondaryLabelColor);
    self.cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelPressed:)];
    self.cancelButton.keyEquivalent = @"\e";
    self.applyButton = [NSButton buttonWithTitle:@"Install" target:self action:@selector(applyPressed:)];
    self.applyButton.keyEquivalent = @"\r";
    self.applyButton.bezelStyle = NSBezelStyleRounded;
    self.applyButton.controlSize = NSControlSizeLarge;
    self.applyButton.contentTintColor = NSColor.controlAccentColor;
    NSStackView *row = CMHorizontalStack(@[scope, [NSView new], self.cancelButton, self.applyButton], 12);
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:28],
        [row.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-28],
        [row.centerYAnchor constraintEqualToAnchor:container.centerYAnchor constant:1],
    ]];
    return container;
}

- (BOOL)statusBool:(NSString *)key {
    return [self.status[key] isEqualToString:@"1"];
}

- (NSInteger)statusInteger:(NSString *)key fallback:(NSInteger)fallback {
    NSString *value = self.status[key];
    NSInteger parsed = value.integerValue;
    return parsed > 0 ? parsed : fallback;
}

- (void)applyStatusToInterfacePreservingForm:(BOOL)preserveForm {
    BOOL installed = [self statusBool:@"installed"];
    BOOL dashboardRunning = [self statusBool:@"dashboard_running"];
    BOOL runnerRunning = [self statusBool:@"runner_running"];
    BOOL running = dashboardRunning && runnerRunning;
    BOOL partial = dashboardRunning != runnerRunning;
    NSString *sourceVersion = self.status[@"source_version"] ?: @"Unknown";
    NSString *installedVersion = self.status[@"installed_version"] ?: @"Not installed";
    NSString *installPath = self.status[@"install_path"] ?: @"—";
    NSInteger webPort = [self statusInteger:@"web_port" fallback:1025];
    NSInteger runnerPort = [self statusInteger:@"runner_port" fallback:10001];
    BOOL updateAvailable = installed
        && ![sourceVersion isEqualToString:@"Unknown"]
        && ![installedVersion isEqualToString:@"Unknown"]
        && ![sourceVersion isEqualToString:installedVersion];

    self.sourceVersionLabel.stringValue = sourceVersion;
    self.installedVersionLabel.stringValue = installedVersion;
    self.installPathLabel.stringValue = installed ? installPath : @"Not installed";
    self.installPathLabel.toolTip = installed ? installPath : nil;
    self.overviewTitle.stringValue = installed ? @"Existing installation found" : @"Ready for first setup";
    self.runningApplyNote.hidden = !running;

    if (updateAvailable) {
        self.updateLabel.stringValue = [NSString stringWithFormat:
            @"Update available: %@ will replace %@. Saved projects and settings stay in place.",
            sourceVersion,
            installedVersion];
        self.updateLabel.hidden = NO;
        self.operationLabel.stringValue = @"An update is ready to apply.";
    } else {
        self.updateLabel.hidden = YES;
        if (!installed) self.operationLabel.stringValue = @"Review the settings below, then install this copy.";
        else if (running) self.operationLabel.stringValue = [NSString stringWithFormat:@"Control Module is running on port %ld.", (long)webPort];
        else if (partial) self.operationLabel.stringValue = @"Only part of Control Module is running. Restart it to recover both services.";
        else self.operationLabel.stringValue = @"Control Module is installed and currently stopped.";
    }

    NSString *statusTitle = @"Not installed";
    NSColor *statusColor = NSColor.controlAccentColor;
    if (running) { statusTitle = @"●  Running"; statusColor = NSColor.systemGreenColor; }
    else if (partial) { statusTitle = @"●  Needs attention"; statusColor = NSColor.systemOrangeColor; }
    else if (installed) { statusTitle = @"●  Stopped"; statusColor = NSColor.secondaryLabelColor; }
    self.statusBadge.stringValue = statusTitle;
    self.statusBadge.textColor = statusColor;

    self.dashboardStatusLabel.stringValue = [NSString stringWithFormat:@"●  Dashboard · %ld — %@", (long)webPort, dashboardRunning ? @"Running" : @"Stopped"];
    self.dashboardStatusLabel.textColor = dashboardRunning ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;
    self.runnerStatusLabel.stringValue = [NSString stringWithFormat:@"●  Runner · %ld — %@", (long)runnerPort, runnerRunning ? @"Running" : @"Stopped"];
    self.runnerStatusLabel.textColor = runnerRunning ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;

    if (!preserveForm || !self.loadedConfiguration) {
        self.portField.stringValue = [NSString stringWithFormat:@"%ld", (long)webPort];
        self.sourceModeControl.selectedSegment = [self.status[@"desktop_access"] isEqualToString:@"desktop"] ? 1 : 0;
        [self updateSourceModeDescription];
        NSString *applications = [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/"];
        [self.locationPopup selectItemAtIndex:[installPath hasPrefix:applications] ? 1 : 0];
        self.shortcutCheckbox.state = [self statusBool:@"shortcut"] ? NSControlStateValueOn : NSControlStateValueOff;
        self.openCheckbox.state = (!installed || running) ? NSControlStateValueOn : NSControlStateValueOff;
        self.loadedConfiguration = YES;
    }
    [self validatePort];
    [self updateControls];
}

- (void)updateControls {
    BOOL busy = self.activeTask != nil;
    BOOL installed = [self statusBool:@"installed"];
    BOOL dashboardRunning = [self statusBool:@"dashboard_running"];
    BOOL runnerRunning = [self statusBool:@"runner_running"];
    BOOL running = dashboardRunning && runnerRunning;
    BOOL anyRunning = dashboardRunning || runnerRunning;
    self.progressIndicator.hidden = !busy;
    if (busy) [self.progressIndicator startAnimation:nil];
    else [self.progressIndicator stopAnimation:nil];
    self.statusBadge.hidden = busy && self.activeOperation != CMOperationStatus;

    BOOL fieldsEnabled = !busy && self.sourceFolder.length > 0;
    self.portField.enabled = fieldsEnabled;
    self.sourceModeControl.enabled = fieldsEnabled;
    self.locationPopup.enabled = fieldsEnabled;
    self.shortcutCheckbox.enabled = fieldsEnabled;
    self.openCheckbox.enabled = fieldsEnabled;
    self.startButton.enabled = fieldsEnabled && installed && !running;
    self.stopButton.enabled = fieldsEnabled && installed && anyRunning;
    self.restartButton.enabled = fieldsEnabled && installed;
    self.refreshButton.enabled = fieldsEnabled;
    self.applyButton.enabled = fieldsEnabled && [self validatePort];
    self.cancelButton.title = busy ? @"Cancel operation" : @"Cancel";

    NSString *sourceVersion = self.status[@"source_version"] ?: @"Unknown";
    NSString *installedVersion = self.status[@"installed_version"] ?: @"Not installed";
    BOOL updateAvailable = installed
        && ![sourceVersion isEqualToString:installedVersion]
        && ![sourceVersion isEqualToString:@"Unknown"];
    self.applyButton.title = !installed ? @"Install" : (updateAvailable ? @"Update & apply" : @"Apply settings");
}

- (BOOL)validatePort {
    NSInteger port = self.portField.stringValue.integerValue;
    BOOL digitsOnly = self.portField.stringValue.length > 0;
    NSCharacterSet *notDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    if ([self.portField.stringValue rangeOfCharacterFromSet:notDigits].location != NSNotFound) digitsOnly = NO;
    BOOL valid = digitsOnly && port >= 1025 && port <= 65535;
    self.portHelpLabel.hidden = valid || self.portField.stringValue.length == 0;
    self.portHelpLabel.stringValue = valid ? @"" : @"Use a whole number from 1025 to 65535.";
    return valid;
}

- (void)portChanged:(id)sender {
    (void)sender;
    [self updateControls];
}

- (void)sourceModeChanged:(id)sender {
    (void)sender;
    [self updateSourceModeDescription];
}

- (void)updateSourceModeDescription {
    self.sourceModeDetail.stringValue = self.sourceModeControl.selectedSegment == 1
        ? @"Runs directly from this checkout. macOS may ask for Desktop access when applicable."
        : @"Runs from Application Support so opening Control Module does not need to read this folder.";
}

- (NSDictionary<NSString *, NSString *> *)decodeStatus:(NSString *)output error:(NSError **)error {
    NSMutableDictionary<NSString *, NSString *> *fields = [NSMutableDictionary dictionary];
    [output enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        (void)stop;
        NSRange equals = [line rangeOfString:@"="];
        if (equals.location == NSNotFound) return;
        NSString *key = [line substringToIndex:equals.location];
        NSString *encoded = [line substringFromIndex:equals.location + 1];
        NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
        NSString *value = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (key.length > 0 && value) fields[key] = value;
    }];
    if (!fields[@"source_version"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ControlModuleSetup"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"The Setup status response was incomplete. Run Setup again from the downloaded Control Module folder."}];
        }
        return nil;
    }
    return fields;
}

- (void)refreshStatusPreservingForm:(BOOL)preserveForm {
    if (self.activeTask || self.sourceFolder.length == 0) return;
    NSString *script = [self.sourceFolder stringByAppendingPathComponent:@"support/mac/manage.sh"];
    self.operationLabel.stringValue = @"Checking this installation…";
    [self runScript:script
          arguments:@[@"status", @"--source", self.sourceFolder]
          operation:CMOperationStatus
          completion:^(NSString *output, NSError *error) {
        if (error) {
            self.operationLabel.stringValue = @"Installation status is unavailable.";
            [self showError:error.localizedDescription];
            [self updateControls];
            return;
        }
        NSError *decodeError = nil;
        NSDictionary *decoded = [self decodeStatus:output error:&decodeError];
        if (!decoded) {
            self.operationLabel.stringValue = @"Installation status is unavailable.";
            [self showError:decodeError.localizedDescription];
            [self updateControls];
            return;
        }
        self.status = decoded;
        [self clearError];
        [self applyStatusToInterfacePreservingForm:preserveForm];
    }];
}

- (void)runScript:(NSString *)script
         arguments:(NSArray<NSString *> *)arguments
         operation:(CMOperation)operation
        completion:(void (^)(NSString *output, NSError *error))completion {
    if (self.activeTask) return;
    self.cancelRequested = NO;
    NSTask *task = [[NSTask alloc] init];
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    task.arguments = [@[script] arrayByAddingObjectsFromArray:arguments];
    NSMutableDictionary<NSString *, NSString *> *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    for (NSString *key in @[
        @"CONTROL_MODULE_CONFIG_DIR",
        @"CONTROL_MODULE_DATA_DIR",
        @"CONTROL_MODULE_SOURCE_DIR",
        @"CONTROL_MODULE_INSTANCE_ID",
        @"CONTROL_MODULE_WEB_PORT",
        @"CONTROL_MODULE_RUNNER_PORT",
        @"CONTROL_MODULE_DIR",
        @"CONTROL_MODULE_NO_OPEN",
    ]) {
        [environment removeObjectForKey:key];
    }
    task.environment = environment;
    task.standardOutput = outputPipe;
    task.standardError = errorPipe;
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finishedTask) {
        NSData *outputData = [outputPipe.fileHandleForReading readDataToEndOfFile];
        NSData *errorData = [errorPipe.fileHandleForReading readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] ?: @"";
        NSString *errorText = [[[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            self.activeTask = nil;
            self.activeOperation = CMOperationNone;
            [self updateControls];
            if (finishedTask.terminationStatus == 0) {
                completion(output, nil);
            } else {
                NSString *message = errorText.length > 0
                    ? errorText
                    : [NSString stringWithFormat:@"The operation ended with status %d.", finishedTask.terminationStatus];
                NSError *error = [NSError errorWithDomain:@"ControlModuleSetup"
                                                     code:finishedTask.terminationStatus
                                                 userInfo:@{NSLocalizedDescriptionKey: message}];
                completion(output, error);
            }
        });
    };

    NSError *launchError = nil;
    self.activeTask = task;
    self.activeOperation = operation;
    [self updateControls];
    if (![task launchAndReturnError:&launchError]) {
        self.activeTask = nil;
        self.activeOperation = CMOperationNone;
        [self updateControls];
        completion(@"", launchError);
    }
}

- (void)showError:(NSString *)message {
    self.errorLabel.stringValue = [@"⚠  " stringByAppendingString:message ?: @"Unknown error"];
    self.errorLabel.hidden = NO;
    self.successLabel.hidden = YES;
}

- (void)showSuccess:(NSString *)message {
    self.successLabel.stringValue = [@"✓  " stringByAppendingString:message ?: @""];
    self.successLabel.hidden = NO;
    self.errorLabel.hidden = YES;
}

- (void)clearError {
    self.errorLabel.hidden = YES;
}

- (void)applyPressed:(id)sender {
    (void)sender;
    if (![self validatePort] || self.activeTask || self.sourceFolder.length == 0) return;
    NSInteger port = self.portField.stringValue.integerValue;
    NSString *destination = self.locationPopup.indexOfSelectedItem == 1
        ? [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Control Module.app"]
        : [self.sourceFolder stringByAppendingPathComponent:@"Control Module.app"];
    NSString *access = self.sourceModeControl.selectedSegment == 1 ? @"desktop" : @"private";
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithArray:@[
        @"--source", self.sourceFolder,
        @"--destination", destination,
        @"--web-port", [NSString stringWithFormat:@"%ld", (long)port],
        @"--desktop-access", access,
    ]];
    if (self.shortcutCheckbox.state == NSControlStateValueOn) [arguments addObject:@"--desktop-shortcut"];
    if (self.openCheckbox.state == NSControlStateValueOn) [arguments addObject:@"--launch"];

    BOOL wasInstalled = [self statusBool:@"installed"];
    [self clearError];
    self.successLabel.hidden = YES;
    self.operationLabel.stringValue = wasInstalled ? @"Applying this installation…" : @"Installing Control Module…";
    NSString *script = [self.sourceFolder stringByAppendingPathComponent:@"support/mac/install.sh"];
    [self runScript:script arguments:arguments operation:CMOperationInstall completion:^(NSString *output, NSError *error) {
        (void)output;
        if (error) {
            self.operationLabel.stringValue = self.cancelRequested ? @"Setup was cancelled." : @"Setup could not finish.";
            [self showError:self.cancelRequested
                ? @"The operation stopped. Existing settings and saved projects were kept."
                : error.localizedDescription];
            return;
        }
        [self showSuccess:wasInstalled
            ? @"Control Module was updated without removing saved projects or settings."
            : @"Control Module was installed successfully."];
        self.operationLabel.stringValue = @"Setup is complete.";
        [self organizeSetupIfNeeded];
        [self refreshStatusPreservingForm:NO];
    }];
}

- (void)runLifecycleAction:(NSString *)action operation:(CMOperation)operation {
    if (self.activeTask || ![self statusBool:@"installed"]) return;
    [self clearError];
    self.successLabel.hidden = YES;
    NSDictionary *messages = @{
        @"start": @"Starting Control Module…",
        @"stop": @"Stopping Control Module safely…",
        @"restart": @"Restarting Control Module safely…",
    };
    self.operationLabel.stringValue = messages[action];
    NSString *script = [self.sourceFolder stringByAppendingPathComponent:@"support/mac/manage.sh"];
    [self runScript:script
          arguments:@[action, @"--source", self.sourceFolder]
          operation:operation
          completion:^(NSString *output, NSError *error) {
        (void)output;
        if (error) {
            self.operationLabel.stringValue = [NSString stringWithFormat:@"The %@ action could not finish.", action];
            [self showError:error.localizedDescription];
        } else {
            [self showSuccess:[action isEqualToString:@"stop"]
                ? @"Control Module and its managed services stopped safely."
                : @"Control Module is running."];
        }
        [self refreshStatusPreservingForm:YES];
    }];
}

- (void)confirmLifecycleAction:(NSString *)action {
    BOOL restart = [action isEqualToString:@"restart"];
    NSAlert *alert = [[NSAlert alloc] init];
    self.lifecycleAlert = alert;
    alert.alertStyle = restart ? NSAlertStyleInformational : NSAlertStyleWarning;
    alert.messageText = restart ? @"Restart Control Module?" : @"Stop Control Module?";
    alert.informativeText = restart
        ? @"The dashboard, runner, and managed projects will stop safely before Control Module opens again."
        : @"The dashboard and runner will close. Any projects managed by this installation will receive their normal safe stop sequence.";
    [alert addButtonWithTitle:restart ? @"Restart" : @"Stop"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        self.lifecycleAlert = nil;
        if (response == NSAlertFirstButtonReturn) {
            [self runLifecycleAction:action operation:restart ? CMOperationRestart : CMOperationStop];
        }
    }];
}

- (void)startPressed:(id)sender {
    (void)sender;
    [self runLifecycleAction:@"start" operation:CMOperationStart];
}

- (void)stopPressed:(id)sender {
    (void)sender;
    [self confirmLifecycleAction:@"stop"];
}

- (void)restartPressed:(id)sender {
    (void)sender;
    [self confirmLifecycleAction:@"restart"];
}

- (void)refreshPressed:(id)sender {
    (void)sender;
    [self refreshStatusPreservingForm:YES];
}

- (void)cancelPressed:(id)sender {
    (void)sender;
    if (self.activeTask.running) {
        self.cancelRequested = YES;
        self.operationLabel.stringValue = @"Cancelling the current operation…";
        [self.activeTask terminate];
    } else {
        [NSApp terminate:nil];
    }
}

- (void)organizeSetupIfNeeded {
    NSString *script = [self.sourceFolder stringByAppendingPathComponent:@"support/mac/store.sh"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:script]) return;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    task.arguments = @[script, self.sourceFolder, NSBundle.mainBundle.bundleURL.path];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    [task launchAndReturnError:nil];
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        CMSetupController *controller = [[CMSetupController alloc] init];
        application.delegate = controller;
        application.activationPolicy = NSApplicationActivationPolicyRegular;
        [application run];
    }
    return 0;
}
