/*eslint-env node*/
/*global exports global*/

'use strict';

exports.isWarning_ = function (severity) {
  return severity == 4;
}

exports.isError_ = function (severity) {
  return severity == 8;
}

exports.getMonaco = function () {
  return global.monaco;
}

exports.registerLanguage_ = function (monaco, language) {
  monaco.languages.register(language);
}

exports.defineTheme_ = function (monaco, theme) {
  monaco.editor.defineTheme(theme.name, theme.themeData);
}

exports.setMonarchTokensProvider_ = function (monaco, languageId, languageDef) {
  return monaco.languages.setMonarchTokensProvider(languageId, languageDef);
}

exports.setModelMarkers_ = function (monaco, model, owner, markers) {
  monaco.editor.setModelMarkers(model, owner, markers);
}

exports.getModelMarkers_ = function (monaco, model) {
  return monaco.editor.getModelMarkers({ resource: model.uri });
}

exports.create_ = function (monaco, nodeId, languageId) {
  const editor = monaco.editor.create(nodeId, {
    language: languageId,
    minimap: {
      enabled: false
    }
  });

  window.addEventListener('resize', function () {
    editor.layout();
  });

  return editor;
}

exports.setTheme_ = function (monaco, themeName) {
  monaco.editor.setTheme(themeName);
}

exports.onDidChangeContent_ = function (editor, handler) {
  editor.getModel().onDidChangeContent(function (event) {
    handler(event)();
  });
}

exports.addExtraTypeScriptLibsJS_ = function (monaco) {
    global.monacoExtraTypeScriptLibs.forEach(function ([dts, dtsFilename]) {
        monaco.languages.typescript.typescriptDefaults.addExtraLib(dts, dtsFilename);
    });
}

exports.setStrictNullChecks_ = function (monaco, bool) {
  var compilerOptions = monaco.languages.typescript.typescriptDefaults.getCompilerOptions();
  compilerOptions['strictNullChecks'] = bool;
  monaco.languages.typescript.typescriptDefaults.setCompilerOptions(compilerOptions);
}

exports.getDecorationRange_ = function (editor, identifier) {
  return editor.getDecorationRange(identifier);
}

exports.setDeltaDecorations_ = function (editor, oldDecorations, newDecorations) {
  return editor.deltaDecorations(oldDecorations, newDecorations);
}

exports.getModel_ = function (editor) {
  return editor.getModel();
}

exports.getEditorId_ = function(editor) {
  return editor.getId();
}

exports.getValue_ = function (model) {
  return model.getValue();
}

exports.setValue_ = function (model, value) {
  return model.setValue(value);
}

exports.getLineCount_ = function (model) {
  return model.getLineCount();
}

exports.setTokensProvider_ = function (monaco, languageId, provider) {
  return monaco.languages.setTokensProvider(languageId, provider);
}

exports.completionItemKind_ = function (name) {
  return monaco.languages.CompletionItemKind[name];
}

exports.markerSeverity_ = function (name) {
  return monaco.MarkerSeverity[name];
}

exports.registerHoverProvider_ = function (monaco, languageId, provider) {
  return monaco.languages.registerHoverProvider(languageId, provider);
}

exports.registerCompletionItemProvider_ = function (monaco, languageId, provider) {
  return monaco.languages.registerCompletionItemProvider(languageId, provider);
}

exports.registerCodeActionProvider_ = function (monaco, languageId, actionProvider) {
  return monaco.languages.registerCodeActionProvider(languageId, actionProvider);
}

exports.registerDocumentFormattingEditProvider_ = function (monaco, languageId, formatter) {
  return monaco.languages.registerDocumentFormattingEditProvider(languageId, formatter);
}

exports.setPosition_ = function (editor, position) {
  editor.setPosition(position);
}

exports.revealRange_ = function (editor, range) {
  editor.revealRange(range);
}

exports.revealRangeInCenter_ = function (editor, range) {
  editor.revealRangeInCenter(range);
}

exports.revealRangeAtTop_ = function (editor, range) {
  editor.revealRangeAtTop(range);
}

exports.revealRangeNearTop_ = function (editor, range) {
  editor.revealRangeNearTop(range);
}

exports.revealLine_ = function (editor, lineNumber) {
  editor.revealLine(lineNumber);
}

exports.layout_ = function (editor) {
  editor.layout();
}

exports.focus_ = function (editor) {
  editor.focus();
}

exports.enableVimBindings_ = function (editor) {
  var statusNode = document.getElementById('statusline');
  var vimMode = global.initVimMode(editor, statusNode);
  return (() => vimMode.dispose());
}

exports.enableEmacsBindings_ = function (editor) {
  var emacsMode = new global.EmacsExtension(editor);
  emacsMode.start();
  return (() => emacsMode.dispose());
}

exports.completionItemKindEq_ = function (a, b) {
  return a == b;
}

exports.completionItemKindOrd_ = function (lt, eq, gt, a, b) {
  if (a < b) {
    return lt;
  } else if (a == b) {
    return eq;
  } else {
    return gt;
  }
}

exports.setReadOnly_ = function (editor, val) {
  editor.updateOptions({ readOnly: val })
}

exports.dispose_ = function (disposable) {
  disposable.dispose();
}
