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
import mediaStorageTest from './test/MediaStorage.test'
import legalMarkdownTest from './test/LegalMarkdown.test'
import legalDocumentTest from './test/LegalDocument.test'
import defaultDataTest from './test/DefaultData.test'
import migrationRunnerTest from './test/MigrationRunner.test'
import errorPresenterTest from './test/ErrorPresenter.test'
import immersiveChromeTest from './test/ImmersiveChrome.test'
import iconTintTest from './test/IconTint.test'
import breakpointTest from './test/Breakpoint.test'
import composeLogicTest from './test/ComposeLogic.test'
import richDocumentTest from './test/RichDocument.test'
import homeLogicTest from './test/HomeLogic.test'
import wrapFlowTest from './test/WrapFlow.test'
import richDocEditorTest from './test/RichDocEditor.test'

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
  mediaStorageTest()
  legalMarkdownTest()
  legalDocumentTest()
  defaultDataTest()
  migrationRunnerTest()
  errorPresenterTest()
  immersiveChromeTest()
  iconTintTest()
  breakpointTest()
  composeLogicTest()
  richDocumentTest()
  homeLogicTest()
  wrapFlowTest()
  richDocEditorTest()
}
