"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("operator", {
  info: () => ipcRenderer.invoke("app:info"),
  run: (args) => ipcRenderer.invoke("operator:run", args),
  abort: () => ipcRenderer.invoke("operator:abort"),
  openSpec: () => ipcRenderer.invoke("dialog:openSpec"),
  getSettings: () => ipcRenderer.invoke("settings:get"),
  saveSettings: (s) => ipcRenderer.invoke("settings:save", s),
  openEnv: () => ipcRenderer.invoke("env:open"),
  githubStatus: () => ipcRenderer.invoke("github:status"),
  linkGitHub: () => ipcRenderer.invoke("github:link"),
  push: (opts) => ipcRenderer.invoke("push:run", opts),
  openStudio: () => ipcRenderer.invoke("studio:open"),
  listProjects: () => ipcRenderer.invoke("projects:list"),
  onOutput: (cb) => ipcRenderer.on("operator:output", (_evt, data) => cb(data)),
});
