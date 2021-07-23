$(document).ready(function() {
  $('#requests').find('a[data-toggle="tab"]').on('shown.bs.tab', function(){
    $($.fn.dataTable.tables(true)).DataTable()
       .columns.adjust();
  });

  $('.requests-datatable').each(function(){
    // 1. Create DataTable
    var dataTableId = $(this).attr('id');
    var typeDropdown = $('select[name=request_type_select][data-table=' + dataTableId + ']');
    var stateDropdown = $('select[name=request_state_select][data-table=' + dataTableId + ']');
    var url = $(this).data('source');
    var pageLength = $(this).data('page-length') || 25;

    $(this).dataTable({
      order: [[0,'desc']],
      columnDefs: [
        // We dont allow ordering by the request link.
        // Columns: created, source, target, requester, type, priority, request link.
        // First column has index 0.
        { orderable: false, targets: [6] }
      ],
      paging: true,
      pagingType: 'full',
      pageLength: pageLength,
      processing: true,
      language: { 
        search: '', searchPlaceholder: "Search...",
        zeroRecords: "Nothing found",
        infoEmpty: "No records available",
        info: "page _PAGE_ of _PAGES_ (_TOTAL_ records)",
        infoFiltered: "",
        processing: "<span>Processing...<i class='fas fa-spinner fa-spin'></span>"
      },
      responsive: true,
      serverSide: true,
      ajax: {
        url: url,
        data: function(d) {
          d.dataTableId = dataTableId;
          d.type = typeDropdown.val();
          d.state = stateDropdown.val();
        }
      },
      stateSave: true,
      stateDuration: 0 // forever
    });
  });
});

// The dropdowns on the package request tabs
$(document).on('change', 'select[data-table]', function() {
  var tableSelector = '#' + $(this).data('table');

  $(tableSelector).DataTable().ajax.reload();
});