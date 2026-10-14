import themeManagerTest from './test/ThemeManager.test'
import localeParsingTest from './test/LocaleParsing.test'
import languageManagerTest from './test/LanguageManager.test'
import appDateFormattersTest from './test/AppDateFormatters.test'
import contentBlockTest from './test/ContentBlock.test'
import journalEntryTest from './test/JournalEntry.test'
import draftTest from './test/Draft.test'
import notebookTest from './test/Notebook.test'
import letterDeliveryTest from './test/LetterDelivery.test'
import uuidTest from './test/Uuid.test'
import databaseTest from './test/Database.test'

export default function testsuite() {
  themeManagerTest()
  localeParsingTest()
  languageManagerTest()
  appDateFormattersTest()
  contentBlockTest()
  journalEntryTest()
  draftTest()
  notebookTest()
  letterDeliveryTest()
  uuidTest()
  databaseTest()
}
