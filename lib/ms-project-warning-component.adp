
<script type="text/javascript" <if @::__csp_nonce@ not nil>nonce="@::__csp_nonce;literal@"</if>>
window.addEventListener('load', function() {
    var el1 = document.getElementById('list_check_all1');
    var el2 = document.getElementById('list_check_all2');
    var el3 = document.getElementById('list_check_all3');
    var el4 = document.getElementById('list_check_all4');

    if (!!el1) el1.addEventListener('click', function() { acs_ListCheckAll('task_without_start_constraint', this.checked) });
    if (!!el2) el2.addEventListener('click', function() { acs_ListCheckAll('task_with_empty_start_end_date', this.checked) });
    if (!!el3) el3.addEventListener('click', function() { acs_ListCheckAll('task_without_start_constraint', this.checked) });
    if (!!el4) el4.addEventListener('click', function() { acs_ListCheckAll('task_without_start_constraint', this.checked) });
});
/*
     document.getElementById('list_check_all1').addEventListener('click', function() { acs_ListCheckAll('task_with_empty_start_end_date', this.checked) });
     document.getElementById('list_check_all2').addEventListener('click', function() { acs_ListCheckAll('task_without_start_constraint', this.checked) });
     document.getElementById('list_check_all3').addEventListener('click', function() { acs_ListCheckAll('task_with_overallocation', this.checked) });
     document.getElementById('list_check_all4').addEventListener('click', function() { acs_ListCheckAll('task_with_overallocation', this.checked) });
*/

</script>


@warnings_html;noquote@

