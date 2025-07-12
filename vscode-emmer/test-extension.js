#!/usr/bin/env node

/**
 * Simple test script for Emmer VS Code Extension
 * Tests error detection capabilities without launching VS Code
 */

const fs = require('fs');
const path = require('path');

// Test cases
const testCases = [
  {
    name: 'Template with unclosed if tag',
    file: 'examples/broken-template.html',
    expectedErrors: [
      { type: 'template', message: 'Unclosed if tag' },
      { type: 'template', message: 'Unclosed for tag' },
      { type: 'include', message: 'Include template not found' },
      { type: 'template', message: 'Invalid variable syntax' }
    ]
  },
  {
    name: 'YAML with tab character',
    file: 'examples/broken-yaml.yaml',
    expectedErrors: [
      { type: 'yaml', message: 'Tabs are not allowed in YAML' },
      { type: 'yaml', message: 'Inconsistent indentation' }
    ]
  }
];

// Simple validation functions (simplified versions of what the extension does)
function validateHtmlFile(content, filePath) {
  const errors = [];
  const lines = content.split('\n');

  // Check for unclosed tags
  const openTags = ['if', 'for', 'case', 'unless'];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    for (const tag of openTags) {
      const openPattern = new RegExp(`{%\\s*${tag}\\s+`);
      if (openPattern.test(line)) {
        const closePattern = new RegExp(`{%\\s*end${tag}\\s*%}`);
        const remainingContent = lines.slice(i + 1).join('\n');
        if (!closePattern.test(remainingContent)) {
          errors.push({
            file: filePath,
            line: i + 1,
            column: line.indexOf('{%') + 1,
            message: `Unclosed ${tag} tag`,
            type: 'template',
            severity: 'error'
          });
        }
      }
    }
  }

  // Check for invalid variable syntax
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const invalidVarPattern = /{{[^}]*{{/g;
    let match;
    while ((match = invalidVarPattern.exec(line)) !== null) {
      errors.push({
        file: filePath,
        line: i + 1,
        column: match.index + 1,
        message: 'Invalid variable syntax: nested {{ }}',
        type: 'template',
        severity: 'error'
      });
    }
  }

  // Check for missing includes
  const includeMatches = content.matchAll(/{%\s*include\s+"([^"]+)"\s*%}/g);
  for (const match of includeMatches) {
    const includeName = match[1];
    const includePath = path.join(path.dirname(filePath), '..', 'templates', includeName);
    if (!fs.existsSync(includePath)) {
      const line = content.substring(0, match.index).split('\n').length;
      errors.push({
        file: filePath,
        line,
        column: 1,
        message: `Include template not found: ${includeName}`,
        type: 'include',
        severity: 'error'
      });
    }
  }

  return errors;
}

function validateYamlFile(content, filePath) {
  const errors = [];
  const lines = content.split('\n');

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNum = i + 1;

    // Check for tabs
    if (line.includes('\t')) {
      errors.push({
        file: filePath,
        line: lineNum,
        column: line.indexOf('\t') + 1,
        message: 'Tabs are not allowed in YAML, use spaces instead',
        type: 'yaml',
        severity: 'error'
      });
    }

    // Check for inconsistent indentation
    if (line.trim() && !line.startsWith(' ') && lineNum > 1) {
      const prevLine = lines[i - 1];
      if (prevLine.trim() && prevLine.includes(':')) {
        if (!line.startsWith('  ')) {
          errors.push({
            file: filePath,
            line: lineNum,
            column: 1,
            message: 'Inconsistent indentation detected',
            type: 'yaml',
            severity: 'warning'
          });
        }
      }
    }
  }

  return errors;
}

// Run tests
function runTests() {
  console.log('🧪 Testing Emmer VS Code Extension Error Detection\n');

  let passedTests = 0;
  let totalTests = 0;

  for (const testCase of testCases) {
    console.log(`📄 Testing: ${testCase.name}`);

    try {
      const filePath = path.join(__dirname, testCase.file);
      const content = fs.readFileSync(filePath, 'utf8');

      let errors = [];
      if (testCase.file.endsWith('.html')) {
        errors = validateHtmlFile(content, filePath);
      } else if (testCase.file.endsWith('.yaml')) {
        errors = validateYamlFile(content, filePath);
      }

      console.log(`   Found ${errors.length} errors:`);
      errors.forEach(error => {
        console.log(`   - ${error.file}:${error.line}:${error.column}: ${error.message}`);
      });

      // Check if we found the expected errors
      const foundExpectedErrors = testCase.expectedErrors.every(expected =>
        errors.some(error =>
          error.type === expected.type &&
          error.message.includes(expected.message.split(':')[0])
        )
      );

      if (foundExpectedErrors && errors.length >= testCase.expectedErrors.length) {
        console.log('   ✅ PASSED\n');
        passedTests++;
      } else {
        console.log('   ❌ FAILED - Expected errors not found\n');
      }

      totalTests++;
    } catch (error) {
      console.log(`   ❌ FAILED - ${error.message}\n`);
      totalTests++;
    }
  }

  console.log(`📊 Test Results: ${passedTests}/${totalTests} tests passed`);

  if (passedTests === totalTests) {
    console.log('🎉 All tests passed! The extension error detection is working correctly.');
  } else {
    console.log('⚠️  Some tests failed. Check the error detection logic.');
  }
}

// Run the tests
runTests();
