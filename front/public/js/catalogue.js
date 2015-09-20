$(document).ready(function() {
    $('#address_sel').hide();
    $('#create_button, #edit_button').click(function() {
        $('#edit_modal').modal('show');
    });

    $('#delete_button').click(function() {
        $('#delete_modal').modal('show');
    });


    $('.dropdown').dropdown();
    $('#org_sel').dropdown({
        onChange: function(value, text, $selectedItem) {
            $('#address_sel').show();
    }
    });

    $('tr').click(function(){
        $(this).toggleClass('active');
    });
});
