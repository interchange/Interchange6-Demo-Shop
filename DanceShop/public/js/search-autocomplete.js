jQuery(document).ready(function($){
    $('#autocomplete').autocomplete({
        serviceUrl: '/ajax-search',
        paramName: 'q',
        dataType: 'json',
        minChars: 3,
        onSelect: function (suggestion) {
            window.location.href = '/' + suggestion.data;
        }
    });
});