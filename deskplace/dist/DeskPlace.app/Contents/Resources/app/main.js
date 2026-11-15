const { app, BrowserWindow, dialog, ipcMain, Menu, screen } = require('electron');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

let mainWindow;
let pendingHtmlPath = null;

function createWindow() {
  const { x, y, width, height } = screen.getPrimaryDisplay().workArea;
  mainWindow = new BrowserWindow({
    x,
    y,
    width,
    height,
    minWidth: 700,
    minHeight: 500,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    title: 'DeskPlace',
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });

  mainWindow.loadFile(path.join(__dirname, 'index.html'));
  mainWindow.once('ready-to-show', () => mainWindow.show());
  mainWindow.webContents.on('did-finish-load', () => {
    if (pendingHtmlPath) {
      const filePath = pendingHtmlPath;
      pendingHtmlPath = null;
      mainWindow.webContents.send('deskplace:load-html', openHtmlPath(filePath));
    }
  });
  mainWindow.on('closed', () => { mainWindow = null; });
}

function deliverHtmlFile(filePath) {
  if (!mainWindow || mainWindow.isDestroyed() || mainWindow.webContents.isLoading()) {
    pendingHtmlPath = filePath;
    return;
  }
  mainWindow.webContents.send('deskplace:load-html', openHtmlPath(filePath));
}

function resizeToPrimaryWorkArea() {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  const { x, y, width, height } = screen.getPrimaryDisplay().workArea;
  mainWindow.setBounds({ x, y, width, height });
}

async function openHtmlFile() {
  if (!mainWindow) return { opened: false };
  const result = await dialog.showOpenDialog(mainWindow, {
    title: 'DeskPlace에서 HTML 열기',
    buttonLabel: '열기',
    properties: ['openFile'],
    filters: [{ name: 'HTML 파일', extensions: ['html', 'htm'] }]
  });
  if (result.canceled || result.filePaths.length === 0) return { opened: false };

  return openHtmlPath(result.filePaths[0]);
}

function openHtmlPath(filePath) {
  const extension = path.extname(filePath).toLowerCase();
  if (!['.html', '.htm'].includes(extension)) return { opened: false };
  return { opened: true, name: path.basename(filePath), url: pathToFileURL(filePath).href };
}

function installAppMenu() {
  const template = [
    {
      label: app.name,
      submenu: [
        { label: 'DeskPlace 정보', role: 'about' },
        { type: 'separator' },
        { label: 'DeskPlace 숨기기', role: 'hide' },
        { label: '다른 앱 숨기기', role: 'hideOthers' },
        { label: '모두 표시', role: 'unhide' },
        { type: 'separator' },
        { label: 'DeskPlace 종료', role: 'quit' }
      ]
    },
    {
      label: '파일',
      submenu: [{ label: 'HTML 파일 열기…', accelerator: 'CommandOrControl+O', click: async () => {
        const result = await openHtmlFile();
        if (result.opened && mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('deskplace:load-html', result);
      } }]
    }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

ipcMain.handle('deskplace:login-item', (_event, enabled) => {
  if (process.platform !== 'darwin') return { supported: false, enabled: false };
  app.setLoginItemSettings({ openAtLogin: Boolean(enabled) });
  return { supported: true, enabled: app.getLoginItemSettings().openAtLogin };
});

ipcMain.handle('deskplace:get-login-item', () => ({
  supported: process.platform === 'darwin',
  enabled: process.platform === 'darwin' && app.getLoginItemSettings().openAtLogin
}));
ipcMain.handle('deskplace:open-html', () => openHtmlFile());
ipcMain.handle('deskplace:reset-wallpaper', () => ({ reset: true }));
ipcMain.handle('deskplace:show-desktop', () => {
  if (process.platform !== 'darwin') {
    mainWindow?.minimize();
    return { supported: false };
  }
  Menu.sendActionToFirstResponder('hideOtherApplications:');
  app.hide();
  return { supported: true };
});

app.whenReady().then(() => {
  installAppMenu();
  createWindow();
  const startupHtml = process.argv.find((arg) => /\.html?$/i.test(arg));
  if (startupHtml && process.platform !== 'darwin') pendingHtmlPath = startupHtml;
  if (pendingHtmlPath) {
    const filePath = pendingHtmlPath;
    pendingHtmlPath = null;
    openHtmlPath(filePath);
  }
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
  screen.on('display-metrics-changed', resizeToPrimaryWorkArea);
  screen.on('display-added', resizeToPrimaryWorkArea);
  screen.on('display-removed', resizeToPrimaryWorkArea);
});

app.on('open-file', (event, filePath) => {
  event.preventDefault();
  if (app.isReady()) deliverHtmlFile(filePath);
  else pendingHtmlPath = filePath;
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
