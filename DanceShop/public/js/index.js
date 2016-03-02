$('.instock').each(function() {
  if ($(this).attr('data')==false) {
      $(this).addClass('invisible');
  }
});
$('.equalheight-offers').equalHeightColumns({
    equalizeRows: true
});
$('.equalheight-products').equalHeightColumns({
    equalizeRows: true,
    checkHeight: 'height'
});
