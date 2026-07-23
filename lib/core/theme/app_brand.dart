import '../config/app_config.dart';

class AppBrand {
  const AppBrand._();

  static const name = 'TaskMaster Pro';
  static const blackGoldLogoAsset =
      'media/app-logo/TaskMaster_Pro_Black_Gold_Transparent_main-logo.png';
  static const darkBlueLogoAsset =
      'media/app-logo/TaskMaster_Pro_Blue_Dark_Transparent.png';
  static const lightLogoAsset =
      'media/app-logo/TaskMaster_Pro_Light_Transparent.png';
  static const logoAsset = blackGoldLogoAsset;
  static const authCallbackUri = 'taskmasterpro://auth/callback';
  static const passwordRecoveryRedirectUri = authCallbackUri;
  static const emailVerificationRedirectUri = authCallbackUri;

  static String logoAssetForTheme(AppThemeChoice choice) {
    return switch (choice) {
      AppThemeChoice.darkBlue => darkBlueLogoAsset,
      AppThemeChoice.blackGold => blackGoldLogoAsset,
      AppThemeChoice.light => lightLogoAsset,
    };
  }
}
