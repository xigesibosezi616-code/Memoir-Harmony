import themeManagerTest from './test/ThemeManager.test'
import localeParsingTest from './test/LocaleParsing.test'
import languageManagerTest from './test/LanguageManager.test'
import appDateFormattersTest from './test/AppDateFormatters.test'

export default function testsuite() {
  themeManagerTest()
  localeParsingTest()
  languageManagerTest()
  appDateFormattersTest()
}
