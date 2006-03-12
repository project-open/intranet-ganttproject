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
    upload_file
}

# ---------------------------------------------------------------
# Defaults & Security
# ---------------------------------------------------------------

set today [db_string today "select to_char(now(), 'YYYY-MM-DD')"]


# ---------------------------------------------------------------
# Procedure: Dependency
# ---------------------------------------------------------------

ad_proc -public im_ganttproject_depend { depend_node task_node } {
    Stores a dependency between two tasks into the database
    Depend: <depend id="2" type="2" difference="0" hardness="Strong"/>
    Task: <task id="1" name="Linux Installation" ...>
            <notes>Note for first task</notes>
            <depend id="2" type="2" difference="0" hardness="Strong"/>
            <customproperty taskproperty-id="tpc0" value="nothing..." />
          </task>
} {
    set task_id_one [$task_node getAttribute id]
    set task_id_two [$depend_node getAttribute id]
    set depend_type [$depend_node getAttribute type]
    set difference [$depend_node getAttribute difference]
    set hardness [$depend_node getAttribute hardness]

    set map_exists_p [db_string map_exists "select count(*) from im_timesheet_task_dependencies where task_id_one = :task_id_one and task_id_two = :task_id_two"]

    if {!$map_exists_p} {
	db_dml insert_dependency "
		insert into im_timesheet_task_dependencies 
		(task_id_one, task_id_two) values (:task_id_one, :task_id_two)
 	"
    }

    set dependency_type_id [db_string dependency_type "select category_id from im_categories where category = :depend_type and category_type = 'Intranet Timesheet Task Dependency Type'" -default ""]
    set hardness_type_id [db_string dependency_type "select category_id from im_categories where category = :hardness and category_type = 'Intranet Timesheet Task Dependency Hardness Type'" -default ""]

    db_dml update_dependency "
	update im_timesheet_task_dependencies set
		dependency_type_id = :dependency_type_id,
		difference = :difference,
		hardness_type_id = :hardness_type_id
	where	task_id_one = :task_id_one
		and task_id_two = :task_id_two
    "
}


# -------------------------------------------------------------------
# Get the file from the user.
# -------------------------------------------------------------------

# Get the file from the user.
# number_of_bytes is the upper-limit
set max_n_bytes [ad_parameter -package_id [im_package_filestorage_id] MaxNumberOfBytes "" 0]
set tmp_filename [ns_queryget upload_file.tmpfile]
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
set html ""

# -------------------------------------------------------------------
# Process Tasks
# -------------------------------------------------------------------

set tasks_node [$root_node selectNodes /project/tasks]

foreach child [$tasks_node childNodes] {

    switch [$child nodeName] {

	"task" {

	    set task_id [$child getAttribute id ""]
	    set task_exists_p [db_0or1row task_info "select * from im_timesheet_tasks where task_id = :task_id"]

	    set task_name [$child getAttribute name ""]
	    set start_date [$child getAttribute start ""]
	    set duration [$child getAttribute duration ""]
	    set percent_completed [$child getAttribute complete "0"]
	    set priority [$child getAttribute priority ""]
	    set expand_p [$child getAttribute expand ""]
	    set description ""

	    set end_date [db_string end_date "select :start_date::date + :duration::integer"]

	    # Process task sub-nodes
	    foreach taskchild [$child childNodes] {

		switch [$taskchild nodeName] {
		    notes { set description [$taskchild nodeValue]}
		    depend { im_ganttproject_depend $taskchild $child }
		    customproperty { }
		}
	    }

	    if {!$task_exists_p} { db_exec_plsql task_insert {} }
	    db_dml task_update {}
	    db_dml update_task2 "
		update im_timesheet_tasks set
			start_date = :start_date,
			end_date = :end_date
		where task_id = :task_id
	    "

	    append html "[ns_quotehtml [$child asXML]]<br>&nbsp;<br>"
	}

	default {
	    # Probably "taskproperties", but 
	    # we don't save them yet.
	}
    }
}



# -------------------------------------------------------------------
# Process Allocations
# <allocation task-id="12391" resource-id="7" function="Default:0" responsible="true" load="100.0"/>
# -------------------------------------------------------------------

set allocations_node [$root_node selectNodes /project/allocations]

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
			:task_id, :user_id
		)"
	    }
	    db_dml update_allocation "
		update im_timesheet_task_allocations set
			role_id	= [im_biz_object_role_full_member],
			percentage = :percentage
		where	task_id = :task_id
			and user_id = :user_id
	    "
	    append html "[ns_quotehtml [$child asXML]]<br>&nbsp;<br>"
	}

	default { }
    }
}




ns_return 200 text/html $html


# ns_return 200 text/xml [$allocations_node asXML -indent 2 -escapeNonASCII]

