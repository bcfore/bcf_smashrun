console.log("This is a test.")

/*
$(document).ready(function() {
  $('.delete').click(function() {
    var to_delete = confirm("Are you sure you want to delete?");
  })
});
*/

$(function() {

  $('form.delete').submit(function(event) {
    event.preventDefault();
    event.stopPropagation();

    var ok = confirm('Are you sure? This cannot be undone!');
    if (ok) {
      //this.submit();
      var form = $(this);

      // Here is where the POST request is made.
      // The response is stored in 'request'.
      var request = $.ajax({
        url: form.attr("action"),
        method: form.attr("method")
      });

      // Here is where we either delete the todo item
      // (b/c that POST returned 204)
      // or simply load the lists page
      // (b/c that POST returned the default of 200)
      request.done(function(data, textStatus, jqXHR) {
        if (jqXHR.status == 204) {
          form.parent("li").remove();
        } else if (jqXHR.status == 200) {
          document.location = data;
        }
      });
    }
  });

});
