// Export only to the user's device; no report data is uploaded.
window.ShopPadReportExport = {
  download(csv, filename) {
    const url = URL.createObjectURL(new Blob([csv], {type:'text/csv;charset=utf-8'}));
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
