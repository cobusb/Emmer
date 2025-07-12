// DaisyUI dark/light mode toggle
const themeToggle = document.getElementById('theme-toggle');
const themeIcon = document.getElementById('theme-icon');
const html = document.documentElement;

function setTheme(theme) {
  html.setAttribute('data-theme', theme);
  localStorage.setItem('theme', theme);
  themeIcon.innerHTML = theme === 'dark'
    ? '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m8.66-13.66l-.71.71M4.05 19.95l-.71.71M21 12h-1M4 12H3m16.95 4.95l-.71-.71M6.34 6.34l-.71-.71M12 5a7 7 0 100 14 7 7 0 000-14z" />'
    : '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m8.66-13.66l-.71.71M4.05 19.95l-.71.71M21 12h-1M4 12H3m16.95 4.95l-.71-.71M6.34 6.34l-.71-.71M12 5a7 7 0 100 14 7 7 0 000-14z" />';
}

if (themeToggle) {
  themeToggle.addEventListener('click', () => {
    const current = html.getAttribute('data-theme');
    setTheme(current === 'dark' ? 'light' : 'dark');
  });
  // On load
  setTheme(localStorage.getItem('theme') || 'light');
}
