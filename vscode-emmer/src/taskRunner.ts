import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import { spawn, ChildProcess } from 'child_process';

export interface EmmerBuildResult {
  success: boolean;
  errors: EmmerError[];
  output: string;
}

export interface EmmerError {
  file: string;
  line: number;
  column: number;
  message: string;
  type: 'template' | 'yaml' | 'build' | 'include';
  severity: 'error' | 'warning';
}

export class EmmerTaskRunner {
  private buildProcess: ChildProcess | null = null;

  async runBuild(workspaceFolder: string, options: {
    sourceDir?: string;
    outputDir?: string;
    templatesDir?: string;
    assetsDir?: string;
    verbose?: boolean;
  } = {}): Promise<EmmerBuildResult> {
    return new Promise((resolve) => {
      const args = [
        'run', '-e',
        `SiteEmmer.build_with_errors([
          source_dir: "${options.sourceDir || 'content'}",
          output_dir: "${options.outputDir || 'dist'}",
          templates_dir: "${options.templatesDir || 'templates'}",
          assets_dir: "${options.assetsDir || 'assets'}",
          verbose: ${options.verbose || false}
        ])`
      ];

      const output: string[] = [];
      const errors: EmmerError[] = [];

      this.buildProcess = spawn('mix', args, {
        cwd: workspaceFolder,
        shell: true
      });

      this.buildProcess.stdout?.on('data', (data) => {
        const text = data.toString();
        output.push(text);

        // Parse structured error output
        this.parseErrorOutput(text, errors);
      });

      this.buildProcess.stderr?.on('data', (data) => {
        const text = data.toString();
        output.push(text);

        // Parse structured error output
        this.parseErrorOutput(text, errors);
      });

      this.buildProcess.on('close', (code) => {
        const result: EmmerBuildResult = {
          success: code === 0,
          errors,
          output: output.join('')
        };
        resolve(result);
      });

      this.buildProcess.on('error', (error) => {
        const result: EmmerBuildResult = {
          success: false,
          errors: [{
            file: '',
            line: 1,
            column: 1,
            message: `Build process failed: ${error.message}`,
            type: 'build',
            severity: 'error'
          }],
          output: output.join('')
        };
        resolve(result);
      });
    });
  }

  async runValidation(workspaceFolder: string, filePath?: string): Promise<EmmerError[]> {
    const errors: EmmerError[] = [];

    if (filePath) {
      // Validate single file
      const ext = path.extname(filePath);
      if (ext === '.html') {
        return this.validateHtmlFile(filePath);
      } else if (ext === '.yaml' || ext === '.yml') {
        return this.validateYamlFile(filePath);
      }
    } else {
      // Validate all files
      const htmlFiles = await this.findFiles(workspaceFolder, '**/*.html');
      const yamlFiles = await this.findFiles(workspaceFolder, '**/*.yaml');

      for (const file of htmlFiles) {
        const fileErrors = await this.validateHtmlFile(file);
        errors.push(...fileErrors);
      }

      for (const file of yamlFiles) {
        const fileErrors = await this.validateYamlFile(file);
        errors.push(...fileErrors);
      }
    }

    return errors;
  }

  private async validateHtmlFile(filePath: string): Promise<EmmerError[]> {
    const errors: EmmerError[] = [];

    try {
      const content = fs.readFileSync(filePath, 'utf8');
      const lines = content.split('\n');

      // Check for layout syntax
      const layoutMatch = content.match(/{%\s*layout\s+"([^"]+)"\s*%}/);
      if (layoutMatch) {
        const layoutName = layoutMatch[1];
        const layoutPath = path.join(path.dirname(filePath), '..', 'templates', layoutName);

        if (!fs.existsSync(layoutPath)) {
          const line = content.substring(0, layoutMatch.index!).split('\n').length;
          errors.push({
            file: filePath,
            line,
            column: 1,
            message: `Layout template not found: ${layoutName}`,
            type: 'include',
            severity: 'error'
          });
        }
      }

      // Check for include syntax
      const includeMatches = content.matchAll(/{%\s*include\s+"([^"]+)"\s*%}/g);
      for (const match of includeMatches) {
        const includeName = match[1];
        const includePath = path.join(path.dirname(filePath), '..', 'templates', includeName);

        if (!fs.existsSync(includePath)) {
          const line = content.substring(0, match.index!).split('\n').length;
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

      // Check for Liquid syntax errors
      const liquidErrors = this.validateLiquidSyntax(content, filePath);
      errors.push(...liquidErrors);

    } catch (error) {
      errors.push({
        file: filePath,
        line: 1,
        column: 1,
        message: `Failed to read file: ${error}`,
        type: 'build',
        severity: 'error'
      });
    }

    return errors;
  }

  private async validateYamlFile(filePath: string): Promise<EmmerError[]> {
    const errors: EmmerError[] = [];

    try {
      const content = fs.readFileSync(filePath, 'utf8');
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

    } catch (error) {
      errors.push({
        file: filePath,
        line: 1,
        column: 1,
        message: `Failed to read YAML file: ${error}`,
        type: 'yaml',
        severity: 'error'
      });
    }

    return errors;
  }

  private validateLiquidSyntax(content: string, filePath: string): EmmerError[] {
    const errors: EmmerError[] = [];
    const lines = content.split('\n');

    // Check for unclosed Liquid tags
    const openTags = ['if', 'for', 'case', 'unless'];

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
              type: 'template',
              severity: 'error'
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
          type: 'template',
          severity: 'error'
        });
      }
    }

    return errors;
  }

  private async findFiles(workspaceFolder: string, pattern: string): Promise<string[]> {
    const files = await vscode.workspace.findFiles(pattern);
    return files.map(file => file.fsPath);
  }

  private parseErrorOutput(output: string, errors: EmmerError[]): void {
    // Parse structured error output from Emmer
    const lines = output.split('\n');

    for (const line of lines) {
      // Look for error patterns like "file:line:column: message"
      const errorMatch = line.match(/^(.+?):(\d+):(\d+):\s*(.+)$/);
      if (errorMatch) {
        const [, file, lineStr, columnStr, message] = errorMatch;
        errors.push({
          file,
          line: parseInt(lineStr),
          column: parseInt(columnStr),
          message,
          type: 'template', // Default type, could be enhanced
          severity: 'error'
        });
      }
    }
  }

  stopBuild(): void {
    if (this.buildProcess) {
      this.buildProcess.kill();
      this.buildProcess = null;
    }
  }
}
