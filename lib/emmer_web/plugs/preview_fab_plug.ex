defmodule EmmerWeb.PreviewFabPlug do
  import Plug.Conn
  import Phoenix.HTML, only: [raw: 1]

  def init(opts), do: opts

  def call(conn, _opts) do
    # This plug is now just a marker - the actual FAB injection happens in the template
    conn
  end

  def generate_fab_menu(emmer) do
    button_position = get_button_position_style(emmer.button_position)
    is_top_position = String.starts_with?(emmer.button_position, "top")

        """
    <div class="fixed z-[9999] p-1" style="#{button_position}">
      <!-- FAB -->
      <button class="btn btn-primary btn-circle btn-lg shadow-lg" onclick="toggleFabMenu()">
        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
        </svg>
      </button>

      <!-- Radial Menu -->
      <div id="fab-menu" class="absolute flex flex-col items-end space-y-4 #{if is_top_position, do: "right-0 mt-4", else: "bottom-16 right-0"}" style="display: none;">
        #{if is_top_position, do: generate_top_position_menu(emmer), else: generate_bottom_position_menu(emmer)}
      </div>
    </div>

    <!-- File Explorer Modal -->
    <div id="file-explorer-modal" class="fixed inset-0 z-[9998] flex items-center justify-center bg-black bg-opacity-40 p-4" style="display: none;">
      <div class="card bg-base-200 shadow-2xl w-full max-w-4xl max-h-[90vh] flex flex-col">
        <div class="card-body flex flex-col p-4 min-h-0">
          <div class="flex justify-between items-center mb-3 flex-shrink-0">
            <h3 class="card-title text-lg">File Explorer</h3>
            <button onclick="closeFileExplorer()" class="btn btn-ghost btn-sm">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>

          <!-- Directory Path -->
          <div class="flex items-center gap-2 mb-3 p-2 bg-base-300 rounded text-xs flex-shrink-0">
            <span class="text-base-content/60">Browse Directory:</span>
            <span class="font-mono" id="file-explorer-path"></span>
          </div>

          <!-- File Tree -->
          <div class="flex-1 min-h-0 overflow-y-auto bg-base-100 rounded border p-3">
            <div class="font-mono text-xs" id="file-explorer-tree">
              <div class="text-center py-8 text-base-content/50">
                <p class="text-sm">Loading files...</p>
              </div>
            </div>
          </div>

          <!-- Footer -->
          <div class="flex justify-between items-center mt-3 pt-2 border-t border-base-300 text-xs flex-shrink-0">
            <span class="text-base-content/60" id="file-explorer-count">
              Loading...
            </span>
            <button onclick="closeFileExplorer()" class="btn btn-ghost btn-xs">Close</button>
          </div>
        </div>
      </div>
    </div>

    <script>
      function toggleFabMenu() {
        const menu = document.getElementById('fab-menu');
        if (menu.style.display === 'none') {
          menu.style.display = 'flex';
        } else {
          menu.style.display = 'none';
        }
      }

      function triggerBuild() {
        const channel = window.previewChannel;
        if (channel) {
          channel.push('refresh', {});
        }
      }

      function refreshPage() {
        window.location.reload();
      }

      function openInNewTab() {
        window.open(window.location.href, '_blank');
      }

      function showErrors() {
        // This would need to be implemented based on your error handling
        alert('Error details would be shown here');
      }

      function openFileExplorer() {
        const modal = document.getElementById('file-explorer-modal');
        const tree = document.getElementById('file-explorer-tree');
        const path = document.getElementById('file-explorer-path');
        const count = document.getElementById('file-explorer-count');

        // Show modal
        modal.style.display = 'flex';

        // Get emmer ID from current URL
        const urlParts = window.location.pathname.split('/');
        const emmerId = urlParts[2]; // /preview/{emmer_id}/...

        // Load file structure
        fetch(`/preview/${emmerId}/files`)
          .then(response => response.json())
          .then(data => {
            path.textContent = data.browse_dir;
            count.textContent = data.files.length > 0 ? `${data.files.length} items` : 'Empty directory';

            if (data.files.length > 0) {
              tree.innerHTML = renderFileTree(data.files);
            } else {
              tree.innerHTML = `
                <div class="text-center py-8 text-base-content/50">
                  <p class="text-sm">No files found</p>
                  <p class="text-xs">This directory is empty or doesn't exist</p>
                </div>
              `;
            }
          })
          .catch(error => {
            console.error('Error loading file structure:', error);
            tree.innerHTML = `
              <div class="text-center py-8 text-base-content/50">
                <p class="text-sm">Error loading files</p>
                <p class="text-xs">${error.message}</p>
              </div>
            `;
          });
      }

      function closeFileExplorer() {
        const modal = document.getElementById('file-explorer-modal');
        modal.style.display = 'none';
      }

      function renderFileTree(files) {
        return files.map(file => {
          const indent = '  '.repeat(file.depth);
          const treeChar = file.is_last ? '└──' : '├──';
          const icon = file.is_dir ? '📁' : (file.is_html ? '📄' : '📄');

          if (file.is_html) {
            return `
              <div class="flex items-center hover:bg-base-200 rounded px-1 py-0.5 group">
                <div class="flex items-center text-base-content/40" style="padding-left: ${file.depth * 12}px">
                  <span>${treeChar}</span>
                </div>
                <span class="flex-1 text-base-content">
                  ${icon} ${file.name}
                </span>
                <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    onclick="openFile('${file.relative_path}')"
                    class="btn btn-primary btn-xs h-6 min-h-6 px-2"
                    title="Open file"
                  >
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"></path>
                    </svg>
                  </button>
                </div>
              </div>
            `;
          } else {
            return `
              <div class="flex items-center hover:bg-base-200 rounded px-1 py-0.5 group">
                <div class="flex items-center text-base-content/40" style="padding-left: ${file.depth * 12}px">
                  <span>${treeChar}</span>
                </div>
                <span class="flex-1 text-base-content">
                  ${icon} ${file.name}
                </span>
              </div>
            `;
          }
        }).join('');
      }

      function openFile(filePath) {
        // Navigate to the file in the preview
        const currentUrl = new URL(window.location.href);
        currentUrl.searchParams.set('file', filePath);
        window.location.href = currentUrl.toString();
        closeFileExplorer();
      }
    </script>
    """
  end

  defp generate_top_position_menu(emmer) do
    """
    <!-- Back to Dashboard -->
    <a href="/" class="btn bg-base-200 btn-circle shadow-md" title="Back to Dashboard">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"></path>
      </svg>
    </a>

    <!-- Show Errors -->
    #{if emmer.last_error && emmer.last_error != [], do: """
    <button class="btn btn-error btn-circle shadow-md" onclick="showErrors()" title="Show Errors">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
      </svg>
    </button>
    """}

    <!-- File explorer -->
    <button class="btn btn-warning btn-circle shadow-md" onclick="openFileExplorer()" title="File Explorer">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2H5a2 2 0 00-2-2z"></path>
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 5a2 2 0 012-2h4a2 2 0 012 2v2H8V5z"></path>
      </svg>
    </button>

    <!-- Open in New Tab -->
    <button class="btn btn-secondary btn-circle shadow-md" onclick="openInNewTab()" title="Open in New Tab">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
      </svg>
    </button>

    <!-- Refresh -->
    <button class="btn btn-info btn-circle shadow-md" onclick="refreshPage()" title="Refresh">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
      </svg>
    </button>

    <!-- Build -->
    <button class="btn btn-success btn-circle shadow-md" onclick="triggerBuild()" title="Build Project">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"></path>
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
      </svg>
    </button>
    """
  end

  defp generate_bottom_position_menu(emmer) do
    """
    <!-- Refresh -->
    <button class="btn btn-info btn-circle shadow-md" onclick="refreshPage()" title="Refresh">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
      </svg>
    </button>

    <!-- Build -->
    <button class="btn btn-success btn-circle shadow-md" onclick="triggerBuild()" title="Build Project">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"></path>
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
      </svg>
    </button>

    <!-- Open in New Tab -->
    <button class="btn btn-secondary btn-circle shadow-md" onclick="openInNewTab()" title="Open in New Tab">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
      </svg>
    </button>

    <!-- File explorer -->
    <button class="btn btn-warning btn-circle shadow-md" onclick="openFileExplorer()" title="File Explorer">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2H5a2 2 0 00-2-2z"></path>
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 5a2 2 0 012-2h4a2 2 0 012 2v2H8V5z"></path>
      </svg>
    </button>

    <!-- Show Errors -->
    #{if emmer.last_error && emmer.last_error != [], do: """
    <button class="btn btn-error btn-circle shadow-md" onclick="showErrors()" title="Show Errors">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
      </svg>
    </button>
    """}

    <!-- Back to Dashboard -->
    <a href="/" class="btn bg-base-200 btn-circle shadow-md" title="Back to Dashboard">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"></path>
      </svg>
    </a>
    """
  end

  defp get_button_position_style(position) do
    case position do
      "bottom-right" -> "bottom: 2rem; right: 2rem;"
      "top-right" -> "top: 2rem; right: 2rem;"
      "bottom-left" -> "bottom: 2rem; left: 2rem;"
      "top-left" -> "top: 2rem; left: 2rem;"
      _ -> "bottom: 2rem; right: 2rem;"
    end
  end


end
