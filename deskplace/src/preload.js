const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('deskplace', {
  getLoginItem: () => ipcRenderer.invoke('deskplace:get-login-item'),
  setLoginItem: (enabled) => ipcRenderer.invoke('deskplace:login-item', enabled),
  openHtml: () => ipcRenderer.invoke('deskplace:open-html'),
  showDesktop: () => ipcRenderer.invoke('deskplace:show-desktop'),
  resetWallpaper: () => ipcRenderer.invoke('deskplace:reset-wallpaper'),
  onHtmlOpened: (callback) => ipcRenderer.on('deskplace:load-html', (_event, file) => callback(file))
});
