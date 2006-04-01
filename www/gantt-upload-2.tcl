# /packages/intranet-ganttproject/www/gantt-upload-2.tcl
#
# Copyright (C) 2003-2004 Project/Open
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

# ---------------------------------------------------------------
# Page Contract
# ---------------------------------------------------------------

ad_page_contract {
    Save/Upload a GanttProject XML structure

    @author frank.bergmann@project-open.com
} {
    { user_id:integer 0 }
    { expiry_date "" }
    { project_id:integer 9689 }
    { security_token "" }
    { upload_gan ""}
    { upload_gif ""}
}

# ---------------------------------------------------------------
# Defaults & Security
# ---------------------------------------------------------------

#ToDo: Security
set today [db_string today "select to_char(now(), 'YYYY-MM-DD')"]
ad_return_top_of_page "[im_header]\n[im_navbar]"


# -------------------------------------------------------------------
# Get the file from the user.
# -------------------------------------------------------------------

# Get the file from the user.
# number_of_bytes is the upper-limit
set max_n_bytes [ad_parameter -package_id [im_package_filestorage_id] MaxNumberOfBytes "" 0]
set tmp_filename [ns_queryget upload_gan.tmpfile]
ns_log Notice "upload-2: tmp_filename=$tmp_filename"
set file_size [file size $tmp_filename]

if { $max_n_bytes && ($file_size > $max_n_bytes) } {
    ad_return_complaint 1 "Your file is larger than the maximum permissible upload size: 
    [util_commify_number $max_n_bytes] bytes"
    return 0
}

if {[catch {
    set fl [open $tmp_filename]
    fconfigure $fl -encoding binary
    set binary_content [read $fl]
    close $fl
} err]} {
    ad_return_complaint 1 "Unable to open file $tmp_filename:
    <br><pre>\n$err</pre>"
    return
}

set doc [dom parse $binary_content]
set root_node [$doc documentElement]


# -------------------------------------------------------------------
# Process Allocations
# <allocation task-id="12391" resource-id="7" function="Default:0" responsible="true" load="100.0"/>
# -------------------------------------------------------------------

set allocations_node [$root_node selectNodes /project/allocations]
ns_write "<h2>Saving Allocations</h2><ul>\n"
foreach child [$allocations_node childNodes] {
    switch [$child nodeName] {
	"allocation" {
	    set task_id [$child getAttribute task-id ""]
	    set resource_id [$child getAttribute resource-id ""]
	    set function [$child getAttribute function ""]
	    set responsible [$child getAttribute responsible ""]
	    set percentage [$child getAttribute load "0"]
	    set allocation_exists_p [db_0or1row allocation_info "select * from im_timesheet_task_allocations where task_id = :task_id and user_id = :resource_id"]

	    set role_id [im_biz_object_role_full_member]
	    if {[string equal "Default:1" $function]} { 
		set role_id [im_biz_object_role_project_manager]
	    }
	    if {!$allocation_exists_p} { 
		db_dml insert_allocation "
		insert into im_timesheet_task_allocations (
			task_id, user_id
		) values (
			:task_id, :resource_id
		)"
	    }
	    db_dml update_allocation "
		update im_timesheet_task_allocations set
			role_id	= [im_biz_object_role_full_member],
			percentage = :percentage
		where	task_id = :task_id
			and user_id = :resource_id
	    "
	    ns_write "<li>[ns_quotehtml [$child asXML]]"
	}
	default { }
    }
}
ns_write "</ul>\n"



# -------------------------------------------------------------------
# Save the new Tasks from GanttProject
# -------------------------------------------------------------------

# Save the tasks to the DB
im_gp_save_tasks $root_node $project_id



# -------------------------------------------------------------------
# Delete the tasks that have been deleted in GanttProject
# -------------------------------------------------------------------

# Extract a tree of tasks from the Database
set xml_tree [im_gp_extract_xml_tree $root_node]
set db_tree [im_gp_extract_db_tree $project_id]
set db_list [lsort -integer -unique [im_gp_flatten $db_tree]]
set xml_list [lsort -integer -unique [im_gp_flatten $xml_tree]]

ns_write "<h2>Extract DB Tree</h2>\n"
ns_write "<ul>\n"
ns_write "<li>DB Tree: $db_tree\n"
ns_write "<li>XML Tree: $xml_tree\n"
ns_write "<li>DB List: $db_list\n"
ns_write "<li>XML List: $xml_list\n"
ns_write "</ul>\n"


# Now calculate the difference between the two lists
#
set diff_list [im_gp_difference $db_list [lappend xml_list $project_id]]

# Deal with the case of an empty diff_list
lappend diff_list 0

ns_write "<h2>Difference List</h2>\n"
ns_write "<ul>\n"
ns_write "<li>Diff List: $diff_list\n"
ns_write "</ul>\n"

set del_projects_sql "
	select	p.project_id
	from	im_projects p
	where	p.project_id in ([join $diff_list ","])
"
db_foreach del_projects $del_projects_sql {
    ns_write "<li>Nuking project '$project_id'\n"
    im_project_nuke $project_id
}


set del_tasks_sql "
	select	p.task_id
	from	im_timesheet_tasks p
	where	p.task_id in ([join $diff_list ","])
"
db_foreach del_tasks $del_tasks_sql {
    ns_write "<li>Nuking task '$task_id'\n"
    im_task_nuke $task_id
}


ns_write [im_footer]
