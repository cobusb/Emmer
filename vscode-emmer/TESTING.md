# Testing the Emmer VS Code Extension

This guide covers all the different ways to test the VS Code extension for Emmer.

## 🧪 Quick Test (Recommended)

Run the automated test script to verify error detection:

```bash
cd vscode-emmer
node test-extension.js
```

This tests the core error detection logic without launching VS Code.

## 🚀 Manual Testing in VS Code

### 1. **Setup Development Environment**

```bash
cd vscode-emmer
npm install
npm run compile
```

### 2. **Launch Extension in Debug Mode**

1. Open the `vscode-emmer` folder in VS Code
2. Press `F5` (or go to Run → Start Debugging)
3. This opens a new VS Code window with your extension loaded

### 3. **Test with Example Files**

1. In the new VS Code window, open the `examples/` folder
2. Open `broken-template.html` - you should see red underlines for errors
3. Open `broken-yaml.yaml` - you should see red underlines for YAML errors
4. Check the Problems panel (View → Problems) to see all errors listed

### 4. **Test Commands**

1. Open Command Palette (`Ctrl+Shift+P` or `Cmd+Shift+P`)
2. Type "Emmer" to see available commands:
   - `Emmer: Build Site`
   - `Emmer: Watch and Build`
   - `Emmer: Validate Templates`
   - `Emmer: Show Build Errors`

### 5. **Test with Real Emmer Project**

1. Create a new Emmer project or open an existing one
2. Add intentional errors to test files:
   ```html
   {% if user.name %}
     Hello {{ user.name }}
   <!-- Missing endif -->
   ```
3. Save the file and watch for error indicators

## 🔧 Automated Testing

### Unit Tests (Future Enhancement)

To add proper unit tests, create a test suite:

```bash
npm install --save-dev @types/mocha @types/node mocha
```

Create `src/test/suite/extension.test.ts`:

```typescript
import * as assert from 'assert';
import * as vscode from 'vscode';
import * as path from 'path';

suite('Extension Test Suite', () => {
  test('Should detect template errors', async () => {
    // Test template validation
  });

  test('Should detect YAML errors', async () => {
    // Test YAML validation
  });

  test('Should show diagnostics', async () => {
    // Test diagnostics display
  });
});
```

### Integration Tests

Test the extension with real Emmer projects:

1. **Create Test Project**:
   ```bash
   mkdir test-emmer-project
   cd test-emmer-project
   # Create content, templates, etc.
   ```

2. **Add Test Files**:
   ```html
   <!-- content/test/index.html -->
   {% layout "layout.html" %}
   {% if user.name %}
     Hello {{ user.name }}
   <!-- Missing endif -->
   ```

3. **Run Extension**:
   - Launch extension in debug mode
   - Open test project
   - Verify errors are detected

## 🎯 Test Scenarios

### Template Error Detection

Test these scenarios in HTML files:

1. **Unclosed Tags**:
   ```html
   {% if user.name %}
     Hello {{ user.name }}
   <!-- Missing endif -->
   ```

2. **Invalid Variable Syntax**:
   ```html
   {{ invalid {{ nested }} braces }}
   ```

3. **Missing Includes**:
   ```html
   {% include "missing-template.html" %}
   ```

4. **Missing Layouts**:
   ```html
   {% layout "missing-layout.html" %}
   ```

### YAML Error Detection

Test these scenarios in YAML files:

1. **Tab Characters**:
   ```yaml
   page:
   	title: My Page  # Tab character
   ```

2. **Inconsistent Indentation**:
   ```yaml
   page:
     title: My Page
   description: Wrong indentation
   ```

3. **Malformed YAML**:
   ```yaml
   page:
     title: My Page
     tags:
       - tag1
       - tag2
   # Missing closing
   ```

### Build Error Detection

Test these scenarios:

1. **Missing Files**:
   - Delete referenced templates
   - Try to build and check for errors

2. **Configuration Issues**:
   - Use invalid directory paths
   - Check for configuration errors

## 🔍 Debugging

### Enable Extension Logs

1. Open Command Palette
2. Run "Developer: Show Logs"
3. Select "Extension Host" to see extension logs

### Debug Extension Code

1. Set breakpoints in `src/extension.ts`
2. Launch extension in debug mode
3. Trigger actions that hit your breakpoints

### Check Diagnostics

1. Open Problems panel
2. Look for "Emmer" source diagnostics
3. Click on errors to navigate to files

## 📊 Test Results

### Expected Behavior

When working correctly, the extension should:

1. **Detect Errors**: Show red underlines for errors
2. **Show Warnings**: Show yellow underlines for warnings
3. **Provide Context**: Show error messages on hover
4. **List in Problems**: Display all errors in Problems panel
5. **Navigate**: Allow clicking errors to jump to location

### Common Issues

1. **No Errors Showing**:
   - Check if file has correct extension (`.html`, `.yaml`)
   - Verify extension is activated
   - Check console for errors

2. **Wrong Error Locations**:
   - Verify line/column calculation
   - Check regex patterns in validation

3. **Extension Not Loading**:
   - Check TypeScript compilation
   - Verify `package.json` configuration
   - Check activation events

## 🚀 Performance Testing

### Large Projects

Test with projects containing:
- 100+ HTML files
- 50+ YAML files
- Complex template hierarchies

### Memory Usage

Monitor memory usage during:
- Initial validation
- File watching
- Large builds

### Response Time

Measure time for:
- File validation on save
- Full workspace validation
- Build execution

## 📝 Test Checklist

Before releasing, verify:

- [ ] Template errors are detected
- [ ] YAML errors are detected
- [ ] Build errors are captured
- [ ] Error locations are accurate
- [ ] Commands work correctly
- [ ] Configuration is respected
- [ ] Performance is acceptable
- [ ] No memory leaks
- [ ] Error messages are helpful
- [ ] Integration with VS Code works

## 🎉 Success Criteria

The extension is working correctly when:

1. **Error Detection**: All expected errors are found
2. **Accuracy**: Error locations match actual issues
3. **Performance**: Validation is fast and responsive
4. **Integration**: Works seamlessly with VS Code
5. **User Experience**: Provides clear, actionable feedback

## 🔄 Continuous Testing

For ongoing development:

1. **Automated Script**: Run `node test-extension.js` before commits
2. **Manual Testing**: Test new features in debug mode
3. **Integration Testing**: Test with real Emmer projects
4. **Performance Testing**: Monitor for regressions

This comprehensive testing approach ensures the extension provides reliable, accurate error detection and a great developer experience.
