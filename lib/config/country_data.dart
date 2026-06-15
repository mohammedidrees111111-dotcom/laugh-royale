class CountryData {
  final String code;
  final String name;
  final String flag;
  final String nameAr;

  const CountryData(this.code, this.name, this.flag, this.nameAr);

  static const List<CountryData> countries = [
    CountryData('SA', 'Saudi Arabia', '🇸🇦', 'المملكة العربية السعودية'),
    CountryData('AE', 'UAE', '🇦🇪', 'الإمارات العربية المتحدة'),
    CountryData('EG', 'Egypt', '🇪🇬', 'مصر'),
    CountryData('KW', 'Kuwait', '🇰🇼', 'الكويت'),
    CountryData('QA', 'Qatar', '🇶🇦', 'قطر'),
    CountryData('BH', 'Bahrain', '🇧🇭', 'البحرين'),
    CountryData('OM', 'Oman', '🇴🇲', 'عُمان'),
    CountryData('JO', 'Jordan', '🇯🇴', 'الأردن'),
    CountryData('LB', 'Lebanon', '🇱🇧', 'لبنان'),
    CountryData('IQ', 'Iraq', '🇮🇶', 'العراق'),
    CountryData('SY', 'Syria', '🇸🇾', 'سوريا'),
    CountryData('PS', 'Palestine', '🇵🇸', 'فلسطين'),
    CountryData('YE', 'Yemen', '🇾🇪', 'اليمن'),
    CountryData('MA', 'Morocco', '🇲🇦', 'المغرب'),
    CountryData('DZ', 'Algeria', '🇩🇿', 'الجزائر'),
    CountryData('TN', 'Tunisia', '🇹🇳', 'تونس'),
    CountryData('LY', 'Libya', '🇱🇾', 'ليبيا'),
    CountryData('SD', 'Sudan', '🇸🇩', 'السودان'),
    CountryData('SO', 'Somalia', '🇸🇴', 'الصومال'),
    CountryData('US', 'United States', '🇺🇸', 'الولايات المتحدة'),
    CountryData('GB', 'United Kingdom', '🇬🇧', 'المملكة المتحدة'),
    CountryData('FR', 'France', '🇫🇷', 'فرنسا'),
    CountryData('DE', 'Germany', '🇩🇪', 'ألمانيا'),
    CountryData('IN', 'India', '🇮🇳', 'الهند'),
    CountryData('PK', 'Pakistan', '🇵🇰', 'باكستان'),
    CountryData('TR', 'Turkey', '🇹🇷', 'تركيا'),
    CountryData('ID', 'Indonesia', '🇮🇩', 'إندونيسيا'),
    CountryData('MY', 'Malaysia', '🇲🇾', 'ماليزيا'),
    CountryData('BR', 'Brazil', '🇧🇷', 'البرازيل'),
    CountryData('NG', 'Nigeria', '🇳🇬', 'نيجيريا'),
  ];
}
