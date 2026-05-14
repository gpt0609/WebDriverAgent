#import "ViewController.h"

#import <arpa/inet.h>
#import <ifaddrs.h>

static NSString *const LobsterWDAHostBundleID = @"app.honey4212.crystal5671";
static NSString *const LobsterWDAHostPort = @"8100";

@interface ViewController ()

@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UILabel *portLabel;
@property (nonatomic, strong) UILabel *bundleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *restartButton;

@end

@implementation ViewController

- (void)viewDidLoad
{
  [super viewDidLoad];

  self.view.backgroundColor = UIColor.systemBackgroundColor;

  UILabel *titleLabel = [self makeLabelWithText:@"Lobster WDA" font:[UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle]];
  titleLabel.textColor = UIColor.labelColor;

  self.statusLabel = [self makeLabelWithText:@"Status: Starting" font:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]];
  self.addressLabel = [self makeLabelWithText:[self.class serviceURLText] font:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]];
  self.portLabel = [self makeLabelWithText:[NSString stringWithFormat:@"Port: %@", LobsterWDAHostPort] font:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]];
  self.bundleLabel = [self makeLabelWithText:[NSString stringWithFormat:@"Bundle ID: %@", LobsterWDAHostBundleID] font:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]];
  self.messageLabel = [self makeLabelWithText:@"Open this app once, then use the Wi-Fi URL from your computer." font:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]];
  self.messageLabel.textColor = UIColor.secondaryLabelColor;

  self.restartButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.restartButton setTitle:@"Restart Service" forState:UIControlStateNormal];
  self.restartButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
  self.restartButton.backgroundColor = UIColor.systemBlueColor;
  [self.restartButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
  self.restartButton.layer.cornerRadius = 8.0;
  self.restartButton.contentEdgeInsets = UIEdgeInsetsMake(12.0, 18.0, 12.0, 18.0);
  [self.restartButton addTarget:self action:@selector(restartButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

  UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[
    titleLabel,
    self.statusLabel,
    self.addressLabel,
    self.portLabel,
    self.bundleLabel,
    self.messageLabel,
    self.restartButton,
  ]];
  stackView.axis = UILayoutConstraintAxisVertical;
  stackView.alignment = UIStackViewAlignmentFill;
  stackView.spacing = 14.0;
  stackView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:stackView];

  UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [stackView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:24.0],
    [stackView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-24.0],
    [stackView.centerYAnchor constraintEqualToAnchor:safeArea.centerYAnchor],
  ]];
}

- (UILabel *)makeLabelWithText:(NSString *)text font:(UIFont *)font
{
  UILabel *label = [[UILabel alloc] init];
  label.text = text;
  label.font = font;
  label.numberOfLines = 0;
  label.adjustsFontForContentSizeCategory = YES;
  return label;
}

- (void)updateServiceRunning:(BOOL)running message:(NSString *)message
{
  self.statusLabel.text = [NSString stringWithFormat:@"Status: %@", running ? @"Running" : @"Stopped"];
  self.addressLabel.text = [self.class serviceURLText];
  self.messageLabel.text = message;
}

- (void)restartButtonTapped:(UIButton *)sender
{
  if (self.restartHandler) {
    self.restartHandler();
  }
}

+ (NSString *)serviceURLText
{
  NSString *ipAddress = self.wifiIPAddress ?: @"0.0.0.0";
  return [NSString stringWithFormat:@"Wi-Fi URL: http://%@:%@", ipAddress, LobsterWDAHostPort];
}

+ (NSString *)wifiIPAddress
{
  struct ifaddrs *interfaces = NULL;
  if (getifaddrs(&interfaces) != 0) {
    return nil;
  }

  NSString *address = nil;
  for (struct ifaddrs *interface = interfaces; interface != NULL; interface = interface->ifa_next) {
    if (interface->ifa_addr == NULL || interface->ifa_addr->sa_family != AF_INET) {
      continue;
    }

    NSString *interfaceName = [NSString stringWithUTF8String:interface->ifa_name];
    if (![interfaceName isEqualToString:@"en0"]) {
      continue;
    }

    char buffer[INET_ADDRSTRLEN];
    const struct sockaddr_in *socketAddress = (const struct sockaddr_in *)interface->ifa_addr;
    if (inet_ntop(AF_INET, &socketAddress->sin_addr, buffer, sizeof(buffer)) != NULL) {
      address = [NSString stringWithUTF8String:buffer];
      break;
    }
  }

  freeifaddrs(interfaces);
  return address;
}

@end
