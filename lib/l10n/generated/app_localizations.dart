import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'队长云加速'**
  String get appTitle;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @servers.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get servers;

  /// No description provided for @subscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscription;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// No description provided for @selectServer.
  ///
  /// In en, this message translates to:
  /// **'Select a server'**
  String get selectServer;

  /// No description provided for @noServers.
  ///
  /// In en, this message translates to:
  /// **'No servers available'**
  String get noServers;

  /// No description provided for @noNodes.
  ///
  /// In en, this message translates to:
  /// **'No nodes'**
  String get noNodes;

  /// No description provided for @updateSubscription.
  ///
  /// In en, this message translates to:
  /// **'Update Subscription'**
  String get updateSubscription;

  /// No description provided for @addSubscription.
  ///
  /// In en, this message translates to:
  /// **'Add Subscription'**
  String get addSubscription;

  /// No description provided for @subscriptionUrl.
  ///
  /// In en, this message translates to:
  /// **'Subscription URL'**
  String get subscriptionUrl;

  /// No description provided for @enterSubscriptionUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter subscription URL'**
  String get enterSubscriptionUrl;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// No description provided for @systemMode.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemMode;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @noAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get noAccount;

  /// No description provided for @hasAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get hasAccount;

  /// No description provided for @invite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get invite;

  /// No description provided for @inviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invite Code'**
  String get inviteCode;

  /// No description provided for @inviteManagement.
  ///
  /// In en, this message translates to:
  /// **'Invite Management'**
  String get inviteManagement;

  /// No description provided for @copySuccess.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copySuccess;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @reLogin.
  ///
  /// In en, this message translates to:
  /// **'Re-login'**
  String get reLogin;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get networkError;

  /// No description provided for @serverError.
  ///
  /// In en, this message translates to:
  /// **'Server error'**
  String get serverError;

  /// No description provided for @traffic.
  ///
  /// In en, this message translates to:
  /// **'Traffic'**
  String get traffic;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @expireDate.
  ///
  /// In en, this message translates to:
  /// **'Expire Date'**
  String get expireDate;

  /// No description provided for @plan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get plan;

  /// No description provided for @remainingTraffic.
  ///
  /// In en, this message translates to:
  /// **'Remaining Traffic'**
  String get remainingTraffic;

  /// No description provided for @usedTraffic.
  ///
  /// In en, this message translates to:
  /// **'Used Traffic'**
  String get usedTraffic;

  /// No description provided for @totalTraffic.
  ///
  /// In en, this message translates to:
  /// **'Total Traffic'**
  String get totalTraffic;

  /// No description provided for @announcement.
  ///
  /// In en, this message translates to:
  /// **'Announcement'**
  String get announcement;

  /// No description provided for @maintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get maintenance;

  /// No description provided for @newVersion.
  ///
  /// In en, this message translates to:
  /// **'New Version Available'**
  String get newVersion;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get updateNow;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @forceUpdate.
  ///
  /// In en, this message translates to:
  /// **'This update is required'**
  String get forceUpdate;

  /// No description provided for @telegram.
  ///
  /// In en, this message translates to:
  /// **'Telegram'**
  String get telegram;

  /// No description provided for @website.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get website;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// No description provided for @customerService.
  ///
  /// In en, this message translates to:
  /// **'Customer Service'**
  String get customerService;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get copyLink;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @refreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Refresh failed'**
  String get refreshFailed;

  /// No description provided for @loadNodesFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load nodes'**
  String get loadNodesFailed;

  /// No description provided for @allNodes.
  ///
  /// In en, this message translates to:
  /// **'All Nodes'**
  String get allNodes;

  /// No description provided for @recommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommended;

  /// No description provided for @latency.
  ///
  /// In en, this message translates to:
  /// **'Latency'**
  String get latency;

  /// No description provided for @testLatency.
  ///
  /// In en, this message translates to:
  /// **'Test Latency'**
  String get testLatency;

  /// No description provided for @protocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get protocol;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get welcomeBack;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @verificationCode.
  ///
  /// In en, this message translates to:
  /// **'Verification Code'**
  String get verificationCode;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send Code'**
  String get sendCode;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to Login'**
  String get backToLogin;

  /// No description provided for @monthPrice.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get monthPrice;

  /// No description provided for @quarterPrice.
  ///
  /// In en, this message translates to:
  /// **'Quarterly'**
  String get quarterPrice;

  /// No description provided for @halfYearPrice.
  ///
  /// In en, this message translates to:
  /// **'Half Yearly'**
  String get halfYearPrice;

  /// No description provided for @yearPrice.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get yearPrice;

  /// No description provided for @twoYearPrice.
  ///
  /// In en, this message translates to:
  /// **'2 Years'**
  String get twoYearPrice;

  /// No description provided for @threeYearPrice.
  ///
  /// In en, this message translates to:
  /// **'3 Years'**
  String get threeYearPrice;

  /// No description provided for @onetimePrice.
  ///
  /// In en, this message translates to:
  /// **'One-time'**
  String get onetimePrice;

  /// No description provided for @resetPrice.
  ///
  /// In en, this message translates to:
  /// **'Reset Traffic'**
  String get resetPrice;

  /// No description provided for @selectPlanFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a plan first'**
  String get selectPlanFirst;

  /// No description provided for @orderCreationFail.
  ///
  /// In en, this message translates to:
  /// **'Order creation failed'**
  String get orderCreationFail;

  /// No description provided for @continuePayment.
  ///
  /// In en, this message translates to:
  /// **'Continue Payment'**
  String get continuePayment;

  /// No description provided for @cancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel Order'**
  String get cancelOrder;

  /// No description provided for @payment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get payment;

  /// No description provided for @orderAndPay.
  ///
  /// In en, this message translates to:
  /// **'Order & Payment'**
  String get orderAndPay;

  /// No description provided for @payMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get payMethod;

  /// No description provided for @selectPlanPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select a plan first'**
  String get selectPlanPrompt;

  /// No description provided for @goSelect.
  ///
  /// In en, this message translates to:
  /// **'Go Select'**
  String get goSelect;

  /// No description provided for @noPlanSelected.
  ///
  /// In en, this message translates to:
  /// **'No Plan Selected'**
  String get noPlanSelected;

  /// No description provided for @subscriptionPeriod.
  ///
  /// In en, this message translates to:
  /// **'Subscription Period'**
  String get subscriptionPeriod;

  /// No description provided for @coupon.
  ///
  /// In en, this message translates to:
  /// **'Coupon (Optional)'**
  String get coupon;

  /// No description provided for @buyNow.
  ///
  /// In en, this message translates to:
  /// **'Buy Now'**
  String get buyNow;

  /// No description provided for @orderSuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment Successful'**
  String get orderSuccess;

  /// No description provided for @confirmPaymentResult.
  ///
  /// In en, this message translates to:
  /// **'Checking payment result...'**
  String get confirmPaymentResult;

  /// No description provided for @order.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get order;

  /// No description provided for @productInfo.
  ///
  /// In en, this message translates to:
  /// **'Product Info'**
  String get productInfo;

  /// No description provided for @startUsing.
  ///
  /// In en, this message translates to:
  /// **'Start Using'**
  String get startUsing;

  /// No description provided for @activated.
  ///
  /// In en, this message translates to:
  /// **'Activated'**
  String get activated;

  /// No description provided for @yourSubscriptionActivated.
  ///
  /// In en, this message translates to:
  /// **'Your subscription has been activated'**
  String get yourSubscriptionActivated;

  /// No description provided for @secureEncryption.
  ///
  /// In en, this message translates to:
  /// **'Secure Encryption'**
  String get secureEncryption;

  /// No description provided for @fastConnection.
  ///
  /// In en, this message translates to:
  /// **'Fast Connection'**
  String get fastConnection;

  /// No description provided for @privacyProtection.
  ///
  /// In en, this message translates to:
  /// **'Privacy Protection'**
  String get privacyProtection;

  /// No description provided for @globalNodes.
  ///
  /// In en, this message translates to:
  /// **'Global Nodes'**
  String get globalNodes;

  /// No description provided for @purchaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Purchase failed'**
  String get purchaseFailed;

  /// No description provided for @unpaidOrder.
  ///
  /// In en, this message translates to:
  /// **'Unpaid Order'**
  String get unpaidOrder;

  /// No description provided for @unpaidOrderMessage.
  ///
  /// In en, this message translates to:
  /// **'You have an unpaid order. Please continue or cancel.'**
  String get unpaidOrderMessage;

  /// No description provided for @cancelingOrder.
  ///
  /// In en, this message translates to:
  /// **'Canceling order...'**
  String get cancelingOrder;

  /// No description provided for @orderCanceled.
  ///
  /// In en, this message translates to:
  /// **'Order canceled, please buy again'**
  String get orderCanceled;

  /// No description provided for @submittingOrder.
  ///
  /// In en, this message translates to:
  /// **'Submitting order...'**
  String get submittingOrder;

  /// No description provided for @cannotOpenPaymentLink.
  ///
  /// In en, this message translates to:
  /// **'Cannot open payment link'**
  String get cannotOpenPaymentLink;

  /// No description provided for @paymentRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment request failed'**
  String get paymentRequestFailed;

  /// No description provided for @paymentException.
  ///
  /// In en, this message translates to:
  /// **'Payment exception'**
  String get paymentException;

  /// No description provided for @paymentResultTimeout.
  ///
  /// In en, this message translates to:
  /// **'Payment timeout, check history later'**
  String get paymentResultTimeout;

  /// No description provided for @queryStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Status query failed'**
  String get queryStatusFailed;

  /// No description provided for @selectNode.
  ///
  /// In en, this message translates to:
  /// **'Select Node'**
  String get selectNode;

  /// No description provided for @nodesAvailable.
  ///
  /// In en, this message translates to:
  /// **'nodes available'**
  String get nodesAvailable;

  /// No description provided for @untested.
  ///
  /// In en, this message translates to:
  /// **'Untested'**
  String get untested;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get syncing;

  /// No description provided for @clickToConnect.
  ///
  /// In en, this message translates to:
  /// **'Click to Connect'**
  String get clickToConnect;

  /// No description provided for @nodeList.
  ///
  /// In en, this message translates to:
  /// **'Node List'**
  String get nodeList;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection Failed'**
  String get connectionFailed;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @basicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic Info'**
  String get basicInfo;

  /// No description provided for @unknownPlan.
  ///
  /// In en, this message translates to:
  /// **'Unknown Plan'**
  String get unknownPlan;

  /// No description provided for @noSubscription.
  ///
  /// In en, this message translates to:
  /// **'No Subscription'**
  String get noSubscription;

  /// No description provided for @trafficResetInfo.
  ///
  /// In en, this message translates to:
  /// **'Traffic resets on'**
  String get trafficResetInfo;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @showWindow.
  ///
  /// In en, this message translates to:
  /// **'Show Window'**
  String get showWindow;

  /// No description provided for @quit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get quit;

  /// No description provided for @generateCode.
  ///
  /// In en, this message translates to:
  /// **'Generate Code'**
  String get generateCode;

  /// No description provided for @generateFailed.
  ///
  /// In en, this message translates to:
  /// **'Generation failed'**
  String get generateFailed;

  /// No description provided for @noInviteData.
  ///
  /// In en, this message translates to:
  /// **'No invite data'**
  String get noInviteData;

  /// No description provided for @noInviteHistory.
  ///
  /// In en, this message translates to:
  /// **'No invite history'**
  String get noInviteHistory;

  /// No description provided for @commissionPercentage.
  ///
  /// In en, this message translates to:
  /// **'Commission'**
  String get commissionPercentage;

  /// No description provided for @totalCommission.
  ///
  /// In en, this message translates to:
  /// **'Total Commission'**
  String get totalCommission;

  /// No description provided for @registeredUsers.
  ///
  /// In en, this message translates to:
  /// **'Registered Users'**
  String get registeredUsers;

  /// No description provided for @pendingCommission.
  ///
  /// In en, this message translates to:
  /// **'Pending Commission'**
  String get pendingCommission;

  /// No description provided for @validOrders.
  ///
  /// In en, this message translates to:
  /// **'Valid Orders'**
  String get validOrders;

  /// No description provided for @myInviteCode.
  ///
  /// In en, this message translates to:
  /// **'My Invite Code'**
  String get myInviteCode;

  /// No description provided for @inviteHistory.
  ///
  /// In en, this message translates to:
  /// **'Invite History'**
  String get inviteHistory;

  /// No description provided for @redeemGiftCard.
  ///
  /// In en, this message translates to:
  /// **'Redeem Gift Card'**
  String get redeemGiftCard;

  /// No description provided for @enterGiftCardCode.
  ///
  /// In en, this message translates to:
  /// **'Enter gift card code'**
  String get enterGiftCardCode;

  /// No description provided for @redeem.
  ///
  /// In en, this message translates to:
  /// **'Redeem'**
  String get redeem;

  /// No description provided for @redeemSuccess.
  ///
  /// In en, this message translates to:
  /// **'Redeem successful'**
  String get redeemSuccess;

  /// No description provided for @redeemFailed.
  ///
  /// In en, this message translates to:
  /// **'Redeem failed'**
  String get redeemFailed;

  /// No description provided for @ixpAccess.
  ///
  /// In en, this message translates to:
  /// **'IXP Access'**
  String get ixpAccess;

  /// No description provided for @fastRouting.
  ///
  /// In en, this message translates to:
  /// **'Fast Routing'**
  String get fastRouting;

  /// No description provided for @highSpeed.
  ///
  /// In en, this message translates to:
  /// **'High Speed'**
  String get highSpeed;

  /// No description provided for @instant4k.
  ///
  /// In en, this message translates to:
  /// **'4K Instant'**
  String get instant4k;

  /// No description provided for @noLogs.
  ///
  /// In en, this message translates to:
  /// **'No Logs'**
  String get noLogs;

  /// No description provided for @strongEncryption.
  ///
  /// In en, this message translates to:
  /// **'Strong Encryption'**
  String get strongEncryption;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @choosePlan.
  ///
  /// In en, this message translates to:
  /// **'Choose Plan'**
  String get choosePlan;

  /// No description provided for @subscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribe;

  /// No description provided for @invalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid code'**
  String get invalidCode;

  /// No description provided for @redeemNow.
  ///
  /// In en, this message translates to:
  /// **'Redeem Now'**
  String get redeemNow;

  /// No description provided for @enterCode.
  ///
  /// In en, this message translates to:
  /// **'Enter your code'**
  String get enterCode;

  /// No description provided for @disconnecting.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting...'**
  String get disconnecting;

  /// No description provided for @loadingConfig.
  ///
  /// In en, this message translates to:
  /// **'Loading config...'**
  String get loadingConfig;

  /// No description provided for @fetchNodesTimeout.
  ///
  /// In en, this message translates to:
  /// **'Fetch nodes timeout'**
  String get fetchNodesTimeout;

  /// No description provided for @inviteFriendsTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite Friends to Earn'**
  String get inviteFriendsTitle;

  /// No description provided for @inviteFriendsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share invite code for high rewards'**
  String get inviteFriendsSubtitle;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'month'**
  String get month;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'year'**
  String get year;

  /// No description provided for @createdAt.
  ///
  /// In en, this message translates to:
  /// **'Created at'**
  String get createdAt;

  /// No description provided for @appDescription.
  ///
  /// In en, this message translates to:
  /// **'队长云加速 is a secure and fast network acceleration service.'**
  String get appDescription;

  /// No description provided for @fastRoutingDesc.
  ///
  /// In en, this message translates to:
  /// **'Fast Routing Optimization'**
  String get fastRoutingDesc;

  /// No description provided for @highSpeedDesc.
  ///
  /// In en, this message translates to:
  /// **'Global Fast Lines'**
  String get highSpeedDesc;

  /// No description provided for @privacyProtectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Privacy Protection'**
  String get privacyProtectionDesc;

  /// No description provided for @strongEncryptionDesc.
  ///
  /// In en, this message translates to:
  /// **'AES-256 Encryption'**
  String get strongEncryptionDesc;

  /// No description provided for @connectionControl.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connectionControl;

  /// No description provided for @subscriptionPlans.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get subscriptionPlans;

  /// No description provided for @accountInfo.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountInfo;

  /// No description provided for @loadingTipConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to secure nodes...'**
  String get loadingTipConnecting;

  /// No description provided for @loadingTipOptimizing.
  ///
  /// In en, this message translates to:
  /// **'Optimizing route path...'**
  String get loadingTipOptimizing;

  /// No description provided for @loadingTipEncrypting.
  ///
  /// In en, this message translates to:
  /// **'Encrypting traffic tunnel...'**
  String get loadingTipEncrypting;

  /// No description provided for @loadingTipVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying server integrity...'**
  String get loadingTipVerifying;

  /// No description provided for @loadingTipSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing configuration...'**
  String get loadingTipSyncing;

  /// No description provided for @loadingTipHandshake.
  ///
  /// In en, this message translates to:
  /// **'Establishing secure handshake...'**
  String get loadingTipHandshake;

  /// No description provided for @loadingTipAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing network latency...'**
  String get loadingTipAnalyzing;

  /// No description provided for @purchasedPlan.
  ///
  /// In en, this message translates to:
  /// **'Purchased Plan'**
  String get purchasedPlan;

  /// No description provided for @proxySettings.
  ///
  /// In en, this message translates to:
  /// **'Proxy Settings'**
  String get proxySettings;

  /// No description provided for @routingMode.
  ///
  /// In en, this message translates to:
  /// **'Routing Mode'**
  String get routingMode;

  /// No description provided for @ruleMode.
  ///
  /// In en, this message translates to:
  /// **'Rule Mode (Smart)'**
  String get ruleMode;

  /// No description provided for @globalMode.
  ///
  /// In en, this message translates to:
  /// **'Global Mode'**
  String get globalMode;

  /// No description provided for @tunMode.
  ///
  /// In en, this message translates to:
  /// **'Tun Mode'**
  String get tunMode;

  /// No description provided for @tunModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Takes over all system traffic'**
  String get tunModeDesc;

  /// No description provided for @subscribeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock premium features'**
  String get subscribeSubtitle;

  /// No description provided for @noPaymentMethods.
  ///
  /// In en, this message translates to:
  /// **'No payment methods available'**
  String get noPaymentMethods;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
