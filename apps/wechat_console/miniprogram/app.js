App({
  controller: null,
  onHide() { if (this.controller) this.controller.hide(); },
  onShow() { if (this.controller) this.controller.show(); }
});
