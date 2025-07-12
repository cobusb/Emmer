"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.EmmerExtension = void 0;
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = __importStar(require("vscode"));
const path = __importStar(require("path"));
const fs = __importStar(require("fs"));
class EmmerExtension {
    constructor() {
        this.buildProcess = null;
        this.isWatching = false;
        this.diagnosticCollection = vscode.languages.createDiagnosticCollection('emmer');
        this.config = this.loadConfig();
    }
    loadConfig() {
        const config = vscode.workspace.getConfiguration('emmer');
        return {
            sourceDir: config.get('sourceDir', 'content'),
            outputDir: config.get('outputDir', 'dist'),
            templatesDir: config.get('templatesDir', 'templates'),
            assetsDir: config.get('assetsDir', 'assets'),
            autoBuild: config.get('autoBuild', false),
            showDiagnostics: config.get('showDiagnostics', true)
        };
    }
    activate(context) {
        // Register commands
        context.subscriptions.push(vscode.commands.registerCommand('emmer.build', () => this.buildSite()), vscode.commands.registerCommand('emmer.watch', () => this.watchSite()), vscode.commands.registerCommand('emmer.validate', () => this.validateTemplates()), vscode.commands.registerCommand('emmer.showErrors', () => this.showErrors()));
        // Register file watchers
        context.subscriptions.push(vscode.workspace.onDidSaveTextDocument((document) => {
            if (this.config.autoBuild && this.isEmmerFile(document.fileName)) {
                this.validateFile(document);
            }
        }), vscode.workspace.onDidChangeConfiguration(() => {
            this.config = this.loadConfig();
        }));
        // Initial validation
        this.validateWorkspace();
    }
    isEmmerFile(filePath) {
        const ext = path.extname(filePath);
        return ext === '.html' || ext === '.yaml' || ext === '.yml';
    }
    async buildSite() {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (!workspaceFolder) {
            vscode.window.showErrorMessage('No workspace folder found');
            return;
        }
        const terminal = vscode.window.createTerminal('Emmer Build');
        terminal.show();
        terminal.sendText(`cd "${workspaceFolder.uri.fsPath}" && mix run -e 'SiteEmmer.build(verbose: true)'`);
    }
    async watchSite() {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (!workspaceFolder) {
            vscode.window.showErrorMessage('No workspace folder found');
            return;
        }
        if (this.isWatching) {
            vscode.window.showInformationMessage('Already watching for changes');
            return;
        }
        this.isWatching = true;
        const terminal = vscode.window.createTerminal('Emmer Watch');
        terminal.show();
        terminal.sendText(`cd "${workspaceFolder.uri.fsPath}" && mix run -e 'SiteEmmer.watch(verbose: true)'`);
    }
    async validateTemplates() {
        const errors = [];
        // Validate HTML templates
        const htmlFiles = await this.findFiles('**/*.html');
        for (const file of htmlFiles) {
            const fileErrors = await this.validateHtmlFile(file);
            errors.push(...fileErrors);
        }
        // Validate YAML files
        const yamlFiles = await this.findFiles('**/*.yaml');
        for (const file of yamlFiles) {
            const fileErrors = await this.validateYamlFile(file);
            errors.push(...fileErrors);
        }
        this.updateDiagnostics(errors);
        this.showValidationResults(errors);
    }
    async validateFile(document) {
        const filePath = document.fileName;
        const ext = path.extname(filePath);
        let errors = [];
        if (ext === '.html') {
            errors = await this.validateHtmlFile(filePath);
        }
        else if (ext === '.yaml' || ext === '.yml') {
            errors = await this.validateYamlFile(filePath);
        }
        this.updateDiagnostics(errors);
    }
    async validateHtmlFile(filePath) {
        const errors = [];
        try {
            const content = fs.readFileSync(filePath, 'utf8');
            const lines = content.split('\n');
            // Check for layout syntax
            const layoutMatch = content.match(/{%\s*layout\s+"([^"]+)"\s*%}/);
            if (layoutMatch) {
                const layoutName = layoutMatch[1];
                const layoutPath = path.join(path.dirname(filePath), '..', this.config.templatesDir, layoutName);
                if (!fs.existsSync(layoutPath)) {
                    const line = content.substring(0, layoutMatch.index).split('\n').length;
                    errors.push({
                        file: filePath,
                        line,
                        column: 1,
                        message: `Layout template not found: ${layoutName}`,
                        severity: 'error',
                        type: 'include'
                    });
                }
            }
            // Check for include syntax
            const includeMatches = content.matchAll(/{%\s*include\s+"([^"]+)"\s*%}/g);
            for (const match of includeMatches) {
                const includeName = match[1];
                const includePath = path.join(path.dirname(filePath), '..', this.config.templatesDir, includeName);
                if (!fs.existsSync(includePath)) {
                    const line = content.substring(0, match.index).split('\n').length;
                    errors.push({
                        file: filePath,
                        line,
                        column: 1,
                        message: `Include template not found: ${includeName}`,
                        severity: 'error',
                        type: 'include'
                    });
                }
            }
            // Check for Liquid syntax errors
            const liquidErrors = this.validateLiquidSyntax(content, filePath);
            errors.push(...liquidErrors);
        }
        catch (error) {
            errors.push({
                file: filePath,
                line: 1,
                column: 1,
                message: `Failed to read file: ${error}`,
                severity: 'error',
                type: 'build'
            });
        }
        return errors;
    }
    async validateYamlFile(filePath) {
        const errors = [];
        try {
            const content = fs.readFileSync(filePath, 'utf8');
            // Basic YAML validation
            const lines = content.split('\n');
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                const lineNum = i + 1;
                // Check for common YAML issues
                if (line.includes('\t')) {
                    errors.push({
                        file: filePath,
                        line: lineNum,
                        column: line.indexOf('\t') + 1,
                        message: 'Tabs are not allowed in YAML, use spaces instead',
                        severity: 'error',
                        type: 'yaml'
                    });
                }
                // Check for inconsistent indentation
                if (line.trim() && !line.startsWith(' ') && lineNum > 1) {
                    const prevLine = lines[i - 1];
                    if (prevLine.trim() && prevLine.includes(':')) {
                        // This might be a missing indentation issue
                        if (!line.startsWith('  ')) {
                            errors.push({
                                file: filePath,
                                line: lineNum,
                                column: 1,
                                message: 'Inconsistent indentation detected',
                                severity: 'warning',
                                type: 'yaml'
                            });
                        }
                    }
                }
            }
        }
        catch (error) {
            errors.push({
                file: filePath,
                line: 1,
                column: 1,
                message: `Failed to read YAML file: ${error}`,
                severity: 'error',
                type: 'yaml'
            });
        }
        return errors;
    }
    validateLiquidSyntax(content, filePath) {
        const errors = [];
        const lines = content.split('\n');
        // Check for unclosed Liquid tags
        const openTags = ['if', 'for', 'case', 'unless'];
        const closeTags = ['endif', 'endfor', 'endcase', 'endunless'];
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const lineNum = i + 1;
            // Check for unclosed tags
            for (const tag of openTags) {
                const openPattern = new RegExp(`{%\\s*${tag}\\s+`);
                if (openPattern.test(line)) {
                    // Look for corresponding close tag
                    const closePattern = new RegExp(`{%\\s*end${tag}\\s*%}`);
                    const remainingContent = lines.slice(i + 1).join('\n');
                    if (!closePattern.test(remainingContent)) {
                        errors.push({
                            file: filePath,
                            line: lineNum,
                            column: line.indexOf('{%') + 1,
                            message: `Unclosed ${tag} tag`,
                            severity: 'error',
                            type: 'template'
                        });
                    }
                }
            }
            // Check for invalid variable syntax
            const invalidVarPattern = /{{[^}]*{{/g;
            let match;
            while ((match = invalidVarPattern.exec(line)) !== null) {
                errors.push({
                    file: filePath,
                    line: lineNum,
                    column: match.index + 1,
                    message: 'Invalid variable syntax: nested {{ }}',
                    severity: 'error',
                    type: 'template'
                });
            }
        }
        return errors;
    }
    async validateWorkspace() {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (!workspaceFolder)
            return;
        // Check if this is an Emmer project
        const mixExsPath = path.join(workspaceFolder.uri.fsPath, 'mix.exs');
        if (fs.existsSync(mixExsPath)) {
            const mixContent = fs.readFileSync(mixExsPath, 'utf8');
            if (mixContent.includes('emmer')) {
                // This is an Emmer project, validate it
                this.validateTemplates();
            }
        }
    }
    async findFiles(pattern) {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (!workspaceFolder)
            return [];
        const files = await vscode.workspace.findFiles(pattern);
        return files.map(file => file.fsPath);
    }
    updateDiagnostics(errors) {
        if (!this.config.showDiagnostics)
            return;
        // Group diagnostics by file URI
        const diagnosticsByFile = new Map();
        for (const error of errors) {
            const uri = vscode.Uri.file(error.file);
            const range = new vscode.Range(error.line - 1, error.column - 1, error.line - 1, error.column + 50);
            const diagnostic = new vscode.Diagnostic(range, error.message, error.severity === 'error' ? vscode.DiagnosticSeverity.Error : vscode.DiagnosticSeverity.Warning);
            diagnostic.source = 'Emmer';
            diagnostic.code = error.type;
            const fileKey = uri.toString();
            if (!diagnosticsByFile.has(fileKey)) {
                diagnosticsByFile.set(fileKey, []);
            }
            diagnosticsByFile.get(fileKey).push(diagnostic);
        }
        // Set diagnostics for each file
        const entries = [];
        for (const [fileKey, diagnostics] of diagnosticsByFile) {
            entries.push([vscode.Uri.parse(fileKey), diagnostics]);
        }
        this.diagnosticCollection.set(entries);
    }
    showValidationResults(errors) {
        const errorCount = errors.filter(e => e.severity === 'error').length;
        const warningCount = errors.filter(e => e.severity === 'warning').length;
        if (errorCount === 0 && warningCount === 0) {
            vscode.window.showInformationMessage('✅ All templates are valid!');
        }
        else {
            const message = `Found ${errorCount} errors and ${warningCount} warnings`;
            vscode.window.showWarningMessage(message);
        }
    }
    showErrors() {
        // Simply show the Problems panel - if there are diagnostics, they'll be visible
        vscode.commands.executeCommand('workbench.actions.view.problems');
        // Show a message about the command
        vscode.window.showInformationMessage('Showing Problems panel - check for Emmer errors');
    }
    dispose() {
        this.diagnosticCollection.dispose();
        if (this.buildProcess) {
            this.buildProcess.kill();
        }
    }
}
exports.EmmerExtension = EmmerExtension;
function activate(context) {
    const extension = new EmmerExtension();
    extension.activate(context);
    context.subscriptions.push({
        dispose: () => extension.dispose()
    });
}
function deactivate() { }
//# sourceMappingURL=extension.js.map