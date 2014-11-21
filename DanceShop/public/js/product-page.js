$( "select.product-attributes-name" ).change(function() {
    var data = {};
    var form = $('form#product_form');
    $.each(form.find("select.product-attributes-name")
      .serializeArray(),function(i,obj) {
        data[obj.name] = obj.value;
    });
    data['sku'] = form.find("input[name=sku]").attr("value");
    data['quantity'] = form.find("input[name=quantity]").attr("value");
    $.ajax({
        type: "POST",
        url: "/check_variant",
        data: data,
    }).done(function(msg) {
        form.find("div.product-price-and-stock").replaceWith(msg.html);
    });
});
