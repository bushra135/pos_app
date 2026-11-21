// Export only to the user's device; no report data is uploaded.
window.ShopPadReportExport = {
  download(workbookBase64, filename) {
    const bytes = Uint8Array.from(atob(workbookBase64), character => character.charCodeAt(0));
    const url = URL.createObjectURL(new Blob([bytes], {type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}));
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    link.style.display = 'none';
    document.body.append(link);
    try {link.click();} finally {
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    }
  }
};
