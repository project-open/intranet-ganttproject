# /packages/intranet-ganttproject/tcl/intranet-ganttproject.tcl
#
# Copyright (C) 2003 - 2009 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    Integrate ]project-open[ tasks and resource assignations
    with GanttProject and its data structure

    @author frank.bergmann@project-open.com
}


# ----------------------------------------------------------------------
# 
# ----------------------------------------------------------------------

ad_proc -public im_package_ganttproject_id {} {
    Returns the package id of the intranet-ganttproject module
} {
    return [util_memoize "im_package_ganttproject_id_helper"]
}

ad_proc -private im_package_ganttproject_id_helper {} {
    return [db_string im_package_core_id {
        select package_id from apm_packages
        where package_key = 'intranet-ganttproject'
    } -default 0]
}


# ----------------------------------------------------------------------
# Recursively write out task structure
# ----------------------------------------------------------------------

ad_proc -public im_ganttproject_write_subtasks { 
    { -default_start_date "" }
    { -default_duration "" }
    project_id
    doc
    tree_node 
} {
    Write out all the specific subtasks of a task or project.
    This procedure asumes that the current task has already 
    been written out and now deals with the subtasks.
} {
    ns_log Notice "im_ganttproject_write_subtasks: doc=$doc, tree_node=$tree_node, project_id=$project_id, default_start_date=$default_start_date, default_duration=$default_duration"

    # Get sub-tasks in the right sort_order
    # Don't include projects, they are handled differently.
    set object_list_list [db_list_of_lists sorted_query "
	select
		p.project_id as object_id,
		o.object_type,
		p.sort_order
	from	
		im_projects p,
		acs_objects o
	where
		p.project_id = o.object_id
		and parent_id = :project_id
                and p.project_type_id = [im_project_type_task]
                and p.project_status_id not in (
			[im_project_status_deleted], 
			[im_project_status_closed]
		)
	order by sort_order
    "]

    foreach object_record $object_list_list {
	set object_id [lindex $object_record 0]

	im_ganttproject_write_task \
	    -default_start_date $default_start_date \
	    -default_duration $default_duration \
	    $object_id \
	    $doc \
	    $tree_node
    }
}


ad_proc -public im_ganttproject_write_task { 
    { -default_start_date "" }
    { -default_duration "" }
    project_id
    doc
    tree_node 
} {
    Write out the information about one specific task and then call
    a recursive routine to write out the stuff below the task.
} {
    ns_log Notice "im_ganttproject_write_task: doc=$doc, tree_node=$tree_node, project_id=$project_id, default_start_date=$default_start_date, default_duration=$default_duration"
    if { [security::secure_conn_p] } {
	set base_url "https://[ad_host][ad_port]"
    } else {
	set base_url "http://[ad_host][ad_port]"
    }
    set task_view_url "$base_url/intranet-timesheet2-tasks/new?task_id="
    set project_view_url "$base_url/intranet/projects/view?project_id="

    # ------------ Get everything about the project -------------
    if {![db_0or1row project_info "
        select  p.*,
		t.*,
		o.object_type,
                p.start_date::date as start_date,
                p.end_date::date as end_date,
		p.end_date::date - p.start_date::date as duration,
                c.company_name
        from    im_projects p
		LEFT OUTER JOIN im_timesheet_tasks t on (p.project_id = t.task_id),
		acs_objects o,
                im_companies c
        where   p.project_id = :project_id
		and p.project_id = o.object_id
                and p.company_id = c.company_id
    "]} {
	ad_return_complaint 1 [lang::message::lookup "" intranet-ganttproject.Project_Not_Found "Didn't find project \#%project_id%"]
	return
    }

    # Make sure some important variables are set to default values
    # because empty values are not accepted by GanttProject:
    #
    if {"" == $percent_completed} { set percent_completed "0" }
    if {"" == $priority} { set priority "1" }
    if {"" == $start_date} { set start_date $default_start_date }
    if {"" == $start_date} { set start_date [db_string today "select to_char(now(), 'YYYY-MM-DD')"] }
    if {"" == $duration} { set duration $default_duration }
    if {"" == $duration} { set duration 1 }
    if {"0" == $duration} { set duration 1 }
    if {$duration < 0} { set duration 1 }

    set project_node [$doc createElement task]
    $tree_node appendChild $project_node
    $project_node setAttribute id $project_id
    $project_node setAttribute name $project_name
    $project_node setAttribute meeting "false"
    $project_node setAttribute start $start_date
    $project_node setAttribute duration $duration
    $project_node setAttribute complete $percent_completed
    $project_node setAttribute priority $priority
    $project_node setAttribute webLink "$project_view_url$project_id"
    $project_node setAttribute expand "true"

    if {$note != ""} {
	set note_node [$doc createElement "notes"]
	$note_node appendChild [$doc createTextNode $note]
	$project_node appendChild $note_node
    }

    # Add dependencies to predecessors 
    # 9650 == 'Intranet Timesheet Task Dependency Type'
    set dependency_sql "
       SELECT	task_id_one AS other_task_id
       FROM	im_timesheet_task_dependencies 
       WHERE    task_id_two = :task_id AND dependency_type_id=9650
    "
    db_foreach dependency $dependency_sql {
	set depend_node [$doc createElement depend]
	$project_node appendChild $depend_node
	$depend_node setAttribute id $other_task_id
	$depend_node setAttribute type 2
	$depend_node setAttribute difference 0
	$depend_node setAttribute hardness "Strong"
    }

    # Custom Property "task_nr"
    # <customproperty taskproperty-id="tpc0" value="linux_install" />
    set task_nr_node [$doc createElement customproperty]
    $project_node appendChild $task_nr_node
    $task_nr_node setAttribute taskproperty-id tpc0
    $task_nr_node setAttribute value $project_nr
   
    # Custom Property "task_id"
    # <customproperty taskproperty-id="tpc1" value="12345" />
    set task_id_node [$doc createElement customproperty]
    $project_node appendChild $task_id_node
    $task_id_node setAttribute taskproperty-id tpc1
    $task_id_node setAttribute value $project_id

    im_ganttproject_write_subtasks \
	-default_start_date $start_date \
	-default_duration $duration \
	$project_id \
	$doc \
	$project_node
}

# ----------------------------------------------------------------------
# Project Page Component 
# ----------------------------------------------------------------------

ad_proc -public im_ganttproject_component { 
    -project_id
    -current_page_url
    -return_url
    -export_var_list
    -forum_type
} {
    Returns a tumbnail of the project and some links for management.
    Check for "project.thumb.xxx" and a "project.full.xxx"
    files with xxx in (gif, png, jpg)
} {
    # 070502 Fraber: Moved into intranet-core/projects/view.tcl
    return ""

    # Is this a "Consulting Project"?
    set consulting_project_category [parameter::get -package_id [im_package_ganttproject_id] -parameter "GanttProjectType" -default "Consulting Project"]
    if {![im_project_has_type $project_id $consulting_project_category]} {
        return ""
    }

    set user_id [ad_get_user_id]
    set thumbnail_size [parameter::get -package_id [im_package_ganttproject_id] -parameter "GanttProjectThumbnailSize" -default "360x360"]
    ns_log Notice "im_ganttproject_component: thumbnail_size=$thumbnail_size"

    # This is the filename to look for in the toplevel folder
    set ganttproject_preview [parameter::get -package_id [im_package_ganttproject_id] -parameter "GanttProjectPreviewFilename" -default "ganttproject.preview"]
    ns_log Notice "im_ganttproject_component: ganttproject_preview=$ganttproject_preview"

    # get the current users permissions for this project
    im_project_permissions $user_id $project_id view read write admin
    if {!$read} { return "" }

    set download_url "/intranet/download/project/$project_id"
    set project_name [db_string project_name "select project_name from im_projects where project_id = :project_id" -default "unknown"]

    set base_path [im_filestorage_base_path project $project_id]
    set base_paths [split $base_path "/"]
    set base_path_len [llength $base_paths]

    set project_files [im_filestorage_find_files $project_id]
    set thumb ""
    set full ""
    foreach project_file $project_files {
	set file_paths [split $project_file "/"]
	set file_paths_len [llength $file_paths]
	set rel_path_list [lrange $file_paths $base_path_len $file_paths_len]
	set rel_path [join $rel_path_list "/"]
	if {[regexp "^$ganttproject_preview\.$thumbnail_size\....\$" $rel_path match]} { set thumb $rel_path}
	if {[regexp "^$ganttproject_preview\....\$" $rel_path match]} { set full $rel_path}
    }

    # Include the thumbnail in the project's view
    set img ""
    if {"" != $thumb} {
	set img "<img src=\"$download_url/$thumb\" title=\"$project_name\" alt=\"$project_name\" border=0>"
    }

    if {"" != $full && $img != ""} {
	set img "<a href=\"$download_url/$full\">$img</a>\n"
    }

    if {"" == $img} {
	set img [lang::message::lookup "" intranet-ganttproject.No_Gantt_preview_available "No Gantt preview available.<br>Please use GanttProject and 'export' a preview."]
    }

    set help [lang::message::lookup "" intranet-ganttproject.ProjectComponentHelp \
    "GanttProject is a free Gantt chart viewer (http://sourceforge.net/project/ganttproject/)"]

    set result "
	$img<br>
	<li><A href=\"[export_vars -base "/intranet-ganttproject/gantt-project.gan" {project_id}]\"
	>[lang::message::lookup "" intranet-ganttproject.Download_Gantt_File "Download GanttProject.gan File"]</A></li>
	<li><A href=\"[export_vars -base "/intranet-ganttproject/openproj-project.xml" {project_id}]\"
	>[lang::message::lookup "" intranet-ganttproject.Download_OpenProj_File "Download OpenProj XML File (beta)"]</A></li>
    "

    set ok_string [lang::message::lookup "" intranet-ganttproject.OK "OK"]

    set bread_crum_path ""
    set folder_type "project"
    set object_id $project_id
    set fs_filename "$ganttproject_preview.png"

    if {$admin} {

	append result "
	<table cellspacing=1 cellpadding=1>
	<tr>
	<td>
	  [im_gif "exp-gan" "Upload GanttProject Schedule"]
	  Upload .gan 
        </td>
	<td>
		<form enctype=multipart/form-data method=POST action=/intranet-ganttproject/gantt-upload-2>
		[export_form_vars return_url project_id]
		<table cellspacing=0 cellpadding=0>
		<tr>
		<td>
			<input type=file name=upload_gan size=10>
		</td>
		<td>
			<input type=submit name=button_gan value='$ok_string'>
		</td>
		</tr>
		</table>
		</form>
	</td></tr>
	</table>
        "
    }
    return $result
}

# ---------------------------------------------------------------
# Get a list of Database task_ids (recursively)
# ---------------------------------------------------------------

ad_proc -public im_gp_extract_db_tree { 
    project_id 
} {
    Returns a list of all task_ids below a top project.
} {
    # We can't use the tree_sortkey query here because we need
    # to deal with sub-projects somewhere in the middel of the
    # structure.

    # We can't leave the DB connection "open" during a recursion,
    # because otherwise the DB connections would get exhausted.
    set task_list [db_list subproject_sql "
	select	project_id
	from	im_projects
	where	parent_id = :project_id
		and project_type_id = [im_project_type_task]
    "]

    set result $project_id
    foreach tid $task_list {
	set result [concat $result [im_gp_extract_db_tree $tid]]
    }
    return $result
}

# ---------------------------------------------------------------
# Procedure: Dependency
# ---------------------------------------------------------------

ad_proc -public im_project_create_dependency { 
    -task_id_one 
    -task_id_two 
    {-depend_type "2"}
    {-difference "0"}
    {-hardness "Strong"}
    -task_hash_array
} {
    Stores a dependency between two tasks into the database
    Depend: <depend id="2" type="2" difference="0" hardness="Strong"/>
    Task: <task id="1" name="Linux Installation" ...>
            <notes>Note for first task</notes>
            <depend id="2" type="2" difference="0" hardness="Strong"/>
            <customproperty taskproperty-id="tpc0" value="nothing..." />
          </task>
} {
    array set task_hash $task_hash_array

    set org_task_id_one task_id_one
    set org_task_id_two task_id_two

    if {[info exists task_hash($task_id_one)]} { set task_id_one $task_hash($task_id_one) }
    if {[info exists task_hash($task_id_two)]} { set task_id_two $task_hash($task_id_two) }

#    ns_write "<li>im_ganttproject_create_dependency($org_task_id_one =&gt; $task_id_one, $org_task_id_two =&gt; $task_id_two, $depend_type, $hardness)\n"

    # ----------------------------------------------------------
    # Check if the two task_ids exist
    #
    set task_objtype_one [db_string task_objtype_one "select object_type from acs_objects where object_id=:task_id_one" -default "unknown"]
    set task_objtype_two [db_string task_objtype_two "select object_type from acs_objects where object_id=:task_id_two" -default "unknown"]
    
    # ----------------------------------------------------------
    #
    set map_exists_p [db_string map_exists "select count(*) from im_timesheet_task_dependencies where task_id_one = :task_id_one and task_id_two = :task_id_two"]

    if {!$map_exists_p} {
	db_dml insert_dependency "
		insert into im_timesheet_task_dependencies 
		(task_id_one, task_id_two) values (:task_id_one, :task_id_two)
 	"
    }

    set dependency_type_id [db_string dependency_type "select category_id from im_categories where category = :depend_type and category_type = 'Intranet Timesheet Task Dependency Type'" -default "9650"]
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
# Save Tasks
# -------------------------------------------------------------------

ad_proc -public im_gp_save_tasks { 
    {-format "gantt" }
    {-create_tasks 1}
    {-save_dependencies 1}
    {-task_hash_array ""}
    {-debug 0}
    root_node 
    super_project_id 
} {
    The top task entries should actually be projects, otherwise
    we return an "incorrect structure" error.
} {
    ns_log Notice "im_gp_save_tasks: format=$format"

    set tasks_node [$root_node selectNodes /project/tasks]

    if {$tasks_node==""} {
	# probably ms project format

	if {[db_string check_gantt_project_entry "
           select count(*)=0 
           from im_gantt_projects 
           where project_id=:super_project_id
        "]} {
	    db_dml add_gantt_project_entry "insert into im_gantt_projects (project_id,xml_elements) values (:super_project_id,'')"
	}

	set xml_elements {}
	foreach child [$root_node childNodes] {
	    set nodeName [$child nodeName]
	    set nodeText [$child text]
	    ns_log Notice "im_gp_save_tasks: nodeName=$nodeName, nodeText=$nodeText"

	    lappend xml_elements $nodeName

	    switch $nodeName {
		"Name" - "Title" - "Manager" - "CalendarUID" - "Calendars" - 
		"Tasks" - "Resources" - "Assignments" - "ScheduleFromStart" {
		    ns_log Notice "im_gp_save_tasks: Ignore"
		    # ignore these
		}
		"StartDate" {
		    ns_log Notice "im_gp_save_tasks: StartDate: Update im_projects.start_date"
		    db_dml project_start_date "
                       UPDATE im_projects SET start_date=:nodeText WHERE project_id=:super_project_id"
		}
		"FinishDate" {		    
		    ns_log Notice "im_gp_save_tasks: StartDate: Update im_projects.end_date"
		    db_dml project_end_date "
                       UPDATE im_projects SET end_date=:nodeText WHERE project_id=:super_project_id"
		}
		default {
		    im_ganttproject_add_import "im_gantt_project" $nodeName
		    set column_name "xml_$nodeName"
		    db_dml update_import_field "
                       UPDATE im_gantt_projects 
                       SET [plsql_utility::generate_oracle_name $column_name]=:nodeText
                       WHERE project_id=:super_project_id
                    "
		}
	    }

	    db_dml update_import_field "
               UPDATE im_gantt_projects 
               SET xml_elements=:xml_elements
               WHERE project_id=:super_project_id
            "
	    
	}

	set tasks_node [$root_node selectNodes -namespace { "project" "http://schemas.microsoft.com/project" } "project:Tasks"]
    }
    
    set super_task_node ""

    set sort_order 0

    # Tricky: The task_hash contains the mapping from gantt_task_id => task_id
    # for both tasks and projects. We have to pass this array around between the
    # recursive calls because TCL doesnt have by-value variables
    array set task_hash $task_hash_array

    foreach child [$tasks_node childNodes] {
	if {$debug} { ns_write "<li>Child: [$child nodeName]\n<ul>\n" }

	switch [$child nodeName] {
	    "task" - "Task" {
		set task_hash_array [im_gp_save_tasks2 \
			-create_tasks $create_tasks \
			-save_dependencies $save_dependencies \
			-debug $debug \
			$child \
			$super_project_id \
			sort_order \
			[array get task_hash] \
		]
		array set task_hash $task_hash_array
	    }
	    default {}
	}

	if {$debug} { ns_write "</ul>\n" }
    }
    # Return the mapping hash
    return [array get task_hash]
}


ad_proc -public im_gp_save_tasks2 {
    {-debug 0}
    -create_tasks
    -save_dependencies
    task_node 
    super_project_id 
    sort_order_name
    task_hash_array
} {
    Stores a single task into the database
} {
    upvar 1 $sort_order_name sort_order
    incr sort_order
    set my_sort_order $sort_order 

    array set task_hash $task_hash_array
    if {$debug} { ns_write "<li>GanttProject($task_node, $super_project_id): '[array get task_hash]'\n" }
    set task_url "/intranet-timesheet2-tasks/new?task_id="

    # What does this mean???
    set org_super_project_id $super_project_id
    if {[info exists task_hash($super_project_id)]} {
        set super_project_id $task_hash($super_project_id)
    }

    # The gantt_project_id as returned from the XML file.
    # This ID does not correspond to a OpenACS object,
    # because GanttProject generates simply consecutive
    # IDs for new objects.
    set gantt_project_id [$task_node getAttribute id ""]

    set task_name [$task_node getAttribute name ""]
    set start_date [$task_node getAttribute start ""]
    set duration [$task_node getAttribute duration ""]
    set percent_completed [$task_node getAttribute complete "0"]
    set priority [$task_node getAttribute priority ""]
    set expand_p [$task_node getAttribute expand ""]
    set end_date [db_string end_date "select :start_date::date + :duration::integer"]
    set is_null 0
    set note ""
    set task_nr ""
    set task_id 0
    set has_subobjects_p 0

    set duration ""
    set remaining_duration ""
    set outline-number ""

    set gantt_field_update {}

    set xml_elements {}

    # ms format uses tags instead of attributes
    foreach taskchild [$task_node childNodes] {
	set nodeName [$taskchild nodeName]
	set nodeText [$taskchild text]
	ns_log Notice "im_gp_save_tasks2: nodeName=$nodeName, nodeText=$nodeText"

        switch $nodeName {
            "Name"              { set task_name [$taskchild text] }
	    "UID"               { set gantt_project_id [$taskchild text] }
	    "IsNull"		{ set is_null [$taskchild text] }
	    "Duration"          { set duration [$taskchild text]     }
	    "RemainingDuration" { set remaining_duration [$taskchild text] }
	    "Start"             { set start_date [$taskchild text] }
	    "Finish"            { set end_date [$taskchild text] }
	    "Priority"          { set priority [$taskchild text] }
	    "Notes"             { set note [$taskchild text] }
	    "OutlineNumber"     { 
		set outline_number [$taskchild text] 
	    }
	    "ExtendedAttribute" {
		set fieldid ""
		set fieldvalue ""
		foreach attrtag [$taskchild childNodes] {
		    switch [$attrtag nodeName] {
			"FieldID" { set fieldid [$attrtag text] }
			"Value"   { set fieldvalue [$attrtag text] }
		    }
		}
		# the following numbers are set by the ms proj format
		# 188744006 : Text20 (used for task_nr)
		# 188744007 : Text21 (used for task_id)
		switch $fieldid {
		    "188744006" { set task_nr $fieldvalue } 
		    "188744007" { set task_id $fieldvalue }
		}
	    }
	    "PredecessorLink" { 
		# this is handled below, because we don't know our task id yet
	    }
	    "OutlineLevel" - "ID" - "CalendarUID" {
		# ignored 
	    }
	    "customproperty" - "task" - "depend" {
		# these are from ganttproject. see below
		continue 
	    }
	    default {
		im_ganttproject_add_import "im_gantt_project" $nodeName
		set column_name "[plsql_utility::generate_oracle_name xml_$nodeName]"
		lappend gantt_field_update "$column_name = '[db_quote $nodeText]'"
	    }
        }
	    
	lappend xml_elements $nodeName
    }

    if {![info exists outline_number]} {
	set outline_number 0
    }

    if {$remaining_duration!="" && $duration!=""} {
	set duration_seconds [ms_project_time_to_seconds $duration]
	set remaining_seconds [ms_project_time_to_seconds $remaining_duration]
	if {$duration_seconds==0} {
	    set percent_completed 100.0
	} else {
	    set percent_completed [expr round(100.0-(100.0/$duration_seconds)*$remaining_seconds)]
	}
    }

    # -----------------------------------------------------
    # Extract the custom properties tpc0 (task_nr) and tpc1 (task_id)
    # for tasks that have been exported out of ]project-open[
    foreach taskchild [$task_node childNodes] {
        switch [$taskchild nodeName] {
            task { set has_subobjects_p 1 }
            customproperty {
		# task_nr and task_id are stored as custprops
		set cust_key [$taskchild getAttribute taskproperty-id ""]
		set cust_value [$taskchild getAttribute value ""]
		switch $cust_key {
		    tpc0 { set task_nr $cust_value}
		    tpc1 { set task_id $cust_value}
		}
            }
        }
    }

    if {$is_null} { return }

    # Normalize task_id from "" to 0
    if {"" == $task_id} { set task_id 0 }

    # Create a reasonable and unique "task_nr" if there wasn't (new task)
    # ToDo: Potentially dangerous - there could be a case with
    # a duplicated gantt_id.
    if {"" == $task_nr} {
	set task_id_zeros $gantt_project_id
	while {[string length $task_id_zeros] < 4} { set task_id_zeros "0$task_id_zeros" }
	set task_nr "task_$task_id_zeros"
    }

    # -----------------------------------------------------
    # Set some default variables for new tasks
    set task_status_id [im_project_status_open]
    set task_type_id [im_project_type_task]
    set uom_id [im_uom_hour]
    set cost_center_id ""
    set material_id [im_material_default_material_id]

    # Get the customer of the super-project
    db_1row super_project_info "
	select	company_id
	from	im_projects
	where	project_id = :super_project_id
    "

    if {$debug} { ns_write "<li>$task_name...\n<li>task_nr='$task_nr', gantt_id=$gantt_project_id, task_id=$task_id" }


    # -----------------------------------------------------
    # Check if we had mapped this task from a GanttProject ID
    # to a different task_id or project_id in the database
    #
    if {[info exists task_hash($gantt_project_id)]} {
	set task_id $task_hash($gantt_project_id)
    }

    # -----------------------------------------------------
    # Check if the task already exists in the database
    set task_exists_p [db_string tasks_exists "
	select	count(*)
	from	im_timesheet_tasks_view
	where	task_id = :task_id
    "]

    # -----------------------------------------------------
    # Give it a second chance to deal with the case that there is
    # already a task with the same task_nr in the same project (same level!):
    set existing_task_id [db_string task_id_from_nr "
	select	task_id 
	from	im_timesheet_tasks_view
	where	project_id = :super_project_id and task_nr = :task_nr
    " -default 0]

    if {0 != $existing_task_id} {
	set task_hash($gantt_project_id) $existing_task_id
	set task_hash("o$outline_number") $existing_task_id
	set task_id $existing_task_id
	set task_exists_p 1
        if {$debug} { ns_write "<li>GanttProject: found task_id=$existing_task_id for task with task_nr=$task_nr" }
    }

    if {$create_tasks && [db_string check_for_existing_task_name "
       select count(*) 
       from im_projects
       where 
          parent_id = :super_project_id and
          company_id = :company_id and
          project_name = :task_name
      "]>0} {
	# ignore this one
	# ad_return_complaint 1 "The task '$task_name' already exists or exists twice in the uploaded file."
	# return [array get task_hash]
    }

    # -----------------------------------------------------
    # Create a new task if:
    # - if task_id=0 (new task created in GanttProject)
    # - if there is a task_id, but it's not in the DB (import from GP)
    if {0 == $task_id || !$task_exists_p} {

	if {$create_tasks} {
	    if {$debug} { ns_write "im_gp_save_tasks2: Creating new task with task_nr='$task_nr'\n" }
	    set task_id [im_exec_dml task_insert "
	    	im_timesheet_task__new (
			null,			-- p_task_id
			'im_timesheet_task',	-- object_type
			now(),			-- creation_date
			null,			-- creation_user
			null,			-- creation_ip
			null,			-- context_id
			:task_nr,
			:task_name,
			:super_project_id,
			:material_id,
			:cost_center_id,
			:uom_id,
			:task_type_id,
			:task_status_id,
			:note
		)"
	    ]

	    # Write Audit Trail
	    im_project_audit -action create -project_id $task_id

	    set task_hash($gantt_project_id) $task_id
	    set task_hash("o$outline_number") $task_id
	}

    } else {
	if {$create_tasks && $debug} { ns_write "Updating existing task\n" }
    }

    # we have the proper task_id now, we can do the dependencies
    foreach taskchild [$task_node childNodes] {
	set nodeName [$taskchild nodeName]
	set nodeText [$taskchild text]
	ns_log Notice "im_gp_save_tasks2: nodeName=$nodeName, nodeText=$nodeText"

        switch $nodeName {
	    "PredecessorLink" {
		if {$save_dependencies} {

		    set linkid ""
		    set linktype ""
		    foreach attrtag [$taskchild childNodes] {
			switch [$attrtag nodeName] {
			    "PredecessorUID" { set linkid [$attrtag text] }
			    # TODO: the next one should obviously not be fixed
			    "Type"           { set linktype 2 }
			}
		    }
		    
		    im_project_create_dependency \
			-task_id_one $task_id \
			-task_id_two $linkid \
			-depend_type $linktype \
			-task_hash_array [array get task_hash]
		}
	    }
        }
    }

    # ---------------------------------------------------------------
    # Process task sub-nodes
    if {$debug} { ns_write "<ul>\n" }
    foreach taskchild [$task_node childNodes] {
	ns_log Notice "im_gp_save_tasks2: process subtasks: nodeName=[$taskchild nodeName]"

	switch [$taskchild nodeName] {
	    notes { 
		set note [$taskchild text] 
	    }
	    depend { 
		if {$save_dependencies} {

		    if {$debug} { ns_write "<li>Creating dependency relationship\n" }

		    im_project_create_dependency \
			-task_id_one [$taskchild getAttribute id] \
			-task_id_two [$task_node getAttribute id] \
			-depend_type [$taskchild getAttribute type] \
			-difference [$taskchild getAttribute difference] \
			-hardness [$taskchild getAttribute hardness] \
			-task_hash_array [array get task_hash]

		}
	    }
	    customproperty { }
	    task {
		# Recursive sub-tasks
		set task_hash_array [im_gp_save_tasks2 \
			-create_tasks $create_tasks \
			-save_dependencies $save_dependencies \
			$taskchild \
			$gantt_project_id \
			sort_order \
			[array get task_hash] \
		]
		array set task_hash $task_hash_array
	    }
	}
    }
    if {$debug} { ns_write "</ul>\n" }

    set outline_number_dot [string last "." $outline_number]
    if {$save_dependencies && $outline_number_dot>=0} {
	set parent_outline_number [string range $outline_number 0 [expr $outline_number_dot-1]]

	if {[info exists task_hash("o$parent_outline_number")]} {
	    set super_project_id $task_hash("o$parent_outline_number")
	}
    }

    db_dml project_update "
	    update im_projects set
		project_name	= :task_name,
		project_nr	= :task_nr,
		parent_id	= :super_project_id,
		start_date	= :start_date,
		end_date	= :end_date,
		note		= :note,
		sort_order	= :my_sort_order,
		percent_completed = :percent_completed
	    where
		project_id = :task_id
    "

    if {[llength $xml_elements]>0} {
	lappend gantt_field_update "xml_elements='[db_quote $xml_elements]'"

	if {[db_string check_gantt_project_entry "
           select count(*)=0 
           from im_gantt_projects 
           where project_id=:task_id
        "]} {
	    db_dml add_gantt_project_entry "
               insert into im_gantt_projects 
                  (project_id,xml_elements) 
                  values (:task_id,'')"
	}
	
	db_dml gantt_project_update "
	    update im_gantt_projects set
                [join $gantt_field_update ,]
	    where
		project_id = :task_id
        " 
    }

    # Write audit trail
    im_project_audit -project_id $task_id

    return [array get task_hash]
}

ad_proc -public ms_project_time_to_seconds {
    time 
} {
    converts the ms project time string to seconds
} {
    regexp {PT([0-9]+)H([0-9]+)M([0-9]+)S} $time all days hours minutes 

    return [expr 60*$minutes+60*60*$hours+60*60*24*$days]
}


# ----------------------------------------------------------------------
# Allocations
#
# Assigns users with a percentage to a task.
# Also adds the user to sub-projects if they are assigned to
# sub-tasks of a sub-project.
# ----------------------------------------------------------------------

ad_proc -public im_gp_save_allocations { 
    {-debug 0}
    allocations_node
    task_hash_array
    resource_hash_array
} {
    Saves allocation information from GanttProject
} {
    array set task_hash $task_hash_array
    array set resource_hash $resource_hash_array

    foreach child [$allocations_node childNodes] {
	switch [$child nodeName] {
	    "allocation" - "Assignment" {
		
		set task_id [$child getAttribute task-id ""]
		set resource_id [$child getAttribute resource-id ""]
		set function [$child getAttribute function ""]
		set responsible [$child getAttribute responsible ""]
		set percentage [$child getAttribute load "0"]
		
		foreach attr [$child childNodes] {
		    set nodeName [$attr nodeName]
		    set nodeText [$attr text]
    		    switch $nodeName {
			"TaskUID" { set task_id $nodeText }
			"ResourceUID" { set resource_id $nodeText }
			"Units" { set percentage [expr round(100.0*$nodeText)] }
		    }
		}

		if {![info exists task_hash($task_id)]} {
		    if {$debug} { ns_write "<li>Allocation: <font color=red>Didn't find task \#$task_id</font>. Skipping... \n" }
		    continue
		}
		set task_id $task_hash($task_id)

		if {![info exists resource_hash($resource_id)]} {
		    if {$debug} { ns_write "<li>Allocation: <font color=red>Didn't find user \#$resource_id</font>. Skipping... \n" }
		    continue
		}
		set resource_id $resource_hash($resource_id)
		if {![string is integer $resource_id]} { continue }

		set role_id [im_biz_object_role_full_member]
		if {[string equal "Default:1" $function]} { 
		    set role_id [im_biz_object_role_project_manager]
		}

		# Add the dude to the task with a given percentage
		im_biz_object_add_role -percentage $percentage $resource_id $task_id $role_id

		set user_name [im_name_from_user_id $resource_id]
		set task_name [db_string task_name "select project_name from im_projects where project_id=:task_id" -default $task_id]
		if {$debug} { ns_write "<li>Allocation: $user_name allocated to $task_name with $percentage%\n" }
		ns_log Notice "im_gp_save_allocations: [$child asXML]"

	    }
	    default { }
	}
    }
}




# ----------------------------------------------------------------------
# Resources
#
# <resource id="8869" name="Andrew Accounting" function="Default:0" contacts="aac@asdf.com... />
#
# ----------------------------------------------------------------------


ad_proc -public im_gp_find_person_for_name { 
    -name
    -email
} {
    Tries to determine the person_id for a name string.
    Uses all kind of fuzzy matching trying to be intuitive...
    Returns "" if it didn't find the name.
} {
    set person_id ""

    # Check for an exact match with Email
    if {"" == $person_id} {
	set person_id [db_string email_check "
		select	min(party_id)
		from	parties
		where	lower(trim(email)) = lower(trim(:email))
        " -default ""]
    }

    # Check for an exact match with username (abbreviation?)
    if {"" == $person_id} {
	set person_id [db_string email_check "
		select	min(user_id)
		from	users
		where	lower(trim(username)) = lower(trim(:name))
        " -default ""]
    }

    # Check for an exact match with the User Name
    if {"" == $person_id} {
        set person_id [db_string resource_id "
		select	min(person_id)
		from	persons
		where	:name = lower(im_name_from_user_id(person_id))
        " -default ""]		
    }

    # Check if we get a single match looking for the pieces of the
    # resources name
    if {"" == $person_id} {
	set name_pieces [split $name " "]
	# Initialize result to the list of all persons
	set result [db_list all_resources "
				select	person_id
				from	persons
	"]

	# Iterate through all parts of the name and 
	#make sure we find all pieces of name in the name
	foreach piece $name_pieces {
	    if {[string length $piece] > 1} {
		set person_ids [db_list resource_id "
					select	person_id
					from	persons
					where	position(:piece in lower(im_name_from_user_id(person_id))) > 0
		"]
		set result [set_intersection $result $person_ids]
	    }
	}

	# Assign the guy only if there is exactly one match.
	if {1 == [llength $result]} {
	    set person_id [lindex $result 0]
	}
    }
    
    return $person_id
}


ad_proc -public im_gp_save_resources { 
    {-debug 0}
    {-project_id 0}
    resources_node
} {
    Saves resource information from GanttProject
} {

    foreach child [$resources_node childNodes] {
	switch [$child nodeName] {
	    "resource" - "Resource" {
		set resource_id [$child getAttribute id ""]
		set name [$child getAttribute name ""]
		set function [$child getAttribute function ""]
		set email [$child getAttribute contacts ""]

		foreach attr [$child childNodes] {
		    switch [$attr nodeName] {
			"UID" { set resource_id [$attr text] }
			"Name" { set name [$attr text] }
			"EmailAddress" { set email [$attr text] } 
		    }
		}
		
		if {$resource_id != "" && $resource_id != 0} {

		    set name [string tolower [string trim $name]]
		    
		    # Do all kinds of fuzzy searching
		    set person_id [im_gp_find_person_for_name -name $name -email $email]
		    
		    if {"" != $person_id} {
			if {$debug} { ns_write "<li>Resource: $name as $function\n" }
			set resource_hash($resource_id) $person_id
			
			# make the resource a member of the project
			im_biz_object_add_role $person_id $project_id [im_biz_object_role_full_member]
			
			set xml_elements {} 
			foreach attr [$child childNodes] {
			    set nodeName [$attr nodeName]
			    set nodeText [$attr text]
			    
			    lappend xml_elements $nodeName

			    switch $nodeName {
				"UID" - "Name" - "EmailAddress" - "ID" - 
				"IsNull" - "MaxUnits" - 
				"PeakUnits" - "OverAllocated" - "CanLevel" -
				"AccrueAt" { }
				default {
				    if {[db_string check_gantt_person_entry "
                                       select count(*)=0 
                                       from im_gantt_persons 
                                       where person_id=:person_id
                                    "]} {
					db_dml add_gantt_person_entry "
                                           insert into im_gantt_persons 
                                           (person_id,xml_elements) values (:person_id,'')"
                                    }

				    im_ganttproject_add_import "im_gantt_person" $nodeName
				    set column_name "[plsql_utility::generate_oracle_name xml_$nodeName]"

				    db_dml update_import_field "UPDATE im_gantt_persons
                                       SET $column_name=:nodeText
                                       WHERE person_id=:person_id
                                       "
				}
			    }
			}

			if {[llength $xml_elements]>0} {
			    db_dml update_import_field "
                               UPDATE im_gantt_persons
                               SET xml_elements=:xml_elements
                               WHERE person_id=:person_id"
			}
		    } else {
			if {$debug} { ns_write "<li>Resource: $name - <font color=red>Unknown Resource</font>\n" }
			set name_frags [split $name " "]
			set first_names [join [lrange $name_frags 0 end-1] ""]
			set last_name [join [lrange $name_frags end end] ""]
			set url [export_vars -base "/intranet/users/new" {email first_names last_name {username $name}}]
			set resource_hash($resource_id) "
			<li>[lang::message::lookup "" intranet-ganttproject.Resource_not_found "Resource %name% (%email%) not found"]:
			<br><a href=\"$url\" target=\"_\">
			[lang::message::lookup "" intranet-ganttproject.Create_Resource "Create %name% (%email%)"]:<br>
			</a><br>
		    "
		    }
		    
		    if {$debug} { ns_write "<li>Resource: ($resource_id) -&gt; $person_id\n" }
		    
		    ns_log Notice "im_gp_save_resources: [$child asXML]"
		}
	    }
	    default { }
	}
    }

    return [array get resource_hash]
}




# ----------------------------------------------------------------------
# Resource Report
# ----------------------------------------------------------------------

ad_proc -public im_ganttproject_resource_component {
    { -start_date "" }
    { -end_date "" }
    { -top_vars "" }
    { -left_vars "user_name_link project_name_link" }
    { -project_id "" }
    { -user_id "" }
    { -customer_id 0 }
    { -user_name_link_opened "" }
    { -return_url "" }
    { -export_var_list "" }
    { -zoom "" }
    { -auto_open 0 }
    { -max_col 8 }
    { -max_row 20 }
} {
    Gantt Resource "Cube"

    @param start_date Hard start of reporting period. Defaults to start of first project
    @param end_date Hard end of replorting period. Defaults to end of last project
    @param left_vars Variables to show at the left-hand side
    @param project_id Id of project(s) to show. Defaults to all active projects
    @param customer_id Id of customer's projects to show
    @param user_name_link_opened List of users with details shown
} {
    set rowclass(0) "roweven"
    set rowclass(1) "rowodd"
    set sigma "&Sigma;"

    if {0 != $customer_id && "" == $project_id} {
	set project_id [db_list pids "
	select	project_id
	from	im_projects
	where	parent_id is null
		and company_id = :customer_id
        "]
    }
    
    # No projects specified? Show the list of all active projects
    if {"" == $project_id} {
        set project_id [db_list pids "
	select	project_id
	from	im_projects
	where	parent_id is null
		and project_status_id = [im_project_status_open]
        "]
    }

    # ToDo: Highlight the sub-project if we're showning the sub-project
    # of a main-project and open the GanttDiagram at the right place
    if {[llength $project_id] == 1} {
	set parent_id [db_string parent_id "select parent_id from im_projects where project_id = :project_id" -default ""]
	while {"" != $parent_id} {
	    set project_id $parent_id
	    set parent_id [db_string parent_id "select parent_id from im_projects where project_id = :project_id" -default ""]
	}
    }

    # ------------------------------------------------------------
    # Start and End-Dat as min/max of selected projects.
    # Note that the sub-projects might "stick out" before and after
    # the main/parent project.
    
    if {"" == $start_date} {
	set start_date [db_string start_date "
	select
		to_char(min(child.start_date), 'YYYY-MM-DD')
	from
		im_projects parent,
		im_projects child
	where
		parent.project_id in ([join $project_id ", "])
		and parent.parent_id is null
		and child.tree_sortkey
			between parent.tree_sortkey
			and tree_right(parent.tree_sortkey)

        "]
    }

    if {"" == $end_date} {
	set end_date [db_string end_date "
	select
		to_char(max(child.end_date), 'YYYY-MM-DD')
	from
		im_projects parent,
		im_projects child,
		acs_rels r,
		im_biz_object_members m
	where
		r.object_id_one = child.project_id
		and r.rel_id = m.rel_id
		and m.percentage > 0

		and parent.project_id in ([join $project_id ", "])
		and parent.parent_id is null
		and child.tree_sortkey
			between parent.tree_sortkey
			and tree_right(parent.tree_sortkey)
        "]
    }

    # Adaptive behaviour - limit the size of the component to a summary
    # suitable for the left/right columns of a project.
    if {$auto_open | "" == $top_vars} {
	set duration_days [db_string dur "select to_date(:end_date, 'YYYY-MM-DD') - to_date(:start_date, 'YYYY-MM-DD')"]
	if {"" == $duration_days} { set duration_days 0 }
	if {$duration_days < 0} { set duration_days 0 }

	set duration_weeks [expr $duration_days / 7]
	set duration_months [expr $duration_days / 30]
	set duration_quarters [expr $duration_days / 91]

	set days_too_long [expr $duration_days > $max_col]
	set weeks_too_long [expr $duration_weeks > $max_col]
	set months_too_long [expr $duration_months > $max_col]
	set quarters_too_long [expr $duration_quarters > $max_col]

	set top_vars "week_of_year day_of_month"
	if {$days_too_long} { set top_vars "month_of_year week_of_year" }
	if {$weeks_too_long} { set top_vars "quarter_of_year month_of_year" }
	if {$months_too_long} { set top_vars "year quarter_of_year" }
	if {$quarters_too_long} { set top_vars "year quarter_of_year" }
    }

    set top_vars [im_ganttproject_zoom_top_vars -zoom $zoom -top_vars $top_vars]

    # ------------------------------------------------------------
    # Define Dimensions
    
    # The complete set of dimensions - used as the key for
    # the "cell" hash. Subtotals are calculated by dropping on
    # or more of these dimensions
    set dimension_vars [concat $top_vars $left_vars]


    # ------------------------------------------------------------
    # URLs to different parts of the system

    set company_url "/intranet/companies/view?company_id="
    set project_url "/intranet/projects/view?project_id="
    set user_url "/intranet/users/view?user_id="
    set this_url [export_vars -base "/intranet-ganttproject/gantt-resources-cube" {start_date end_date left_vars customer_id} ]
    foreach pid $project_id { append this_url "&project_id=$pid" }


    # ------------------------------------------------------------
    # Conditional SQL Where-Clause
    #
    
    set criteria [list]
    if {"" != $customer_id && 0 != $customer_id} { lappend criteria "parent.company_id = :customer_id" }
    if {"" != $project_id && 0 != $project_id} { lappend criteria "parent.project_id in ([join $project_id ", "])" }
    if {"" != $user_id && 0 != $user_id} { lappend criteria "u.user_id in ([join $user_id ","])" }

    set where_clause [join $criteria " and\n\t\t\t"]
    if { ![empty_string_p $where_clause] } {
	set where_clause " and $where_clause"
    }
    

    # ------------------------------------------------------------
    # Define the report SQL
    #
    
    # Inner - Try to be as selective as possible for the relevant data from the fact table.
    set inner_sql "
		select
		        child.*,
		        u.user_id,
			m.percentage as perc,
			d.d
		from
		        im_projects parent,
		        im_projects child,
		        acs_rels r
		        LEFT OUTER JOIN im_biz_object_members m on (r.rel_id = m.rel_id),
		        users u,
		        ( select im_day_enumerator_weekdays as d
		          from im_day_enumerator_weekdays(
				to_date(:start_date, 'YYYY-MM-DD'), 
				to_date(:end_date, 'YYYY-MM-DD')
			) ) d
		where
		        r.object_id_one = child.project_id
		        and r.object_id_two = u.user_id
		        and parent.project_status_id in ([join [im_sub_categories [im_project_status_open]] ","])
		        and parent.parent_id is null
		        and child.tree_sortkey 
				between parent.tree_sortkey 
				and tree_right(parent.tree_sortkey)
		        and d.d 
				between child.start_date 
				and child.end_date
			$where_clause
    "


    # Aggregate additional/important fields to the fact table.
    set middle_sql "
	select
		h.*,
		trunc(h.perc) as percentage,
		'<a href=${user_url}'||user_id||'>'||im_name_from_id(h.user_id)||'</a>' as user_name_link,
		'<a href=${project_url}'||project_id||'>'||project_name||'</a>' as project_name_link,
		to_char(h.d, 'YYYY') as year,
		'<!--' || to_char(h.d, 'YYYY') || '-->Q' || to_char(h.d, 'Q') as quarter_of_year,
		'<!--' || to_char(h.d, 'YYYY-MM') || '-->' || to_char(h.d, 'Mon') as month_of_year,
		'<!--' || to_char(h.d, 'YYYY-MM') || '-->W' || to_char(h.d, 'IW') as week_of_year,
		'<!--' || to_char(h.d, 'YYYY-MM') || '-->' || to_char(h.d, 'DD') as day_of_month
	from	($inner_sql) h
	where	h.perc is not null
    "

    set outer_sql "
	select
		sum(h.percentage) as percentage,
		[join $dimension_vars ",\n\t"]
	from
		($middle_sql) h
	group by
		[join $dimension_vars ",\n\t"]
    "


    # ------------------------------------------------------------
    # Create upper date dimension


    # Top scale is a list of lists such as {{2006 01} {2006 02} ...}
    # The last element of the list the grand total sum.
    set top_scale_plain [db_list_of_lists top_scale "
	select distinct	[join $top_vars ", "]
	from		($middle_sql) c
	order by	[join $top_vars ", "]
    "]
    lappend top_scale_plain [list $sigma $sigma $sigma $sigma $sigma $sigma]


    # Insert subtotal columns whenever a scale changes
    set top_scale [list]
    set last_item [lindex $top_scale_plain 0]
    foreach scale_item $top_scale_plain {
	
	for {set i [expr [llength $last_item]-2]} {$i >= 0} {set i [expr $i-1]} {
	    set last_var [lindex $last_item $i]
	    set cur_var [lindex $scale_item $i]
	    if {$last_var != $cur_var} {
		set item_sigma [lrange $last_item 0 $i]
		while {[llength $item_sigma] < [llength $last_item]} { lappend item_sigma $sigma }
		lappend top_scale $item_sigma
	    }
	}
	
	lappend top_scale $scale_item
	set last_item $scale_item
    }


    # ------------------------------------------------------------
    # Create a sorted left dimension
    
    # Scale is a list of lists. Example: {{2006 01} {2006 02} ...}
    # The last element is the grand total.
    set left_scale_plain [db_list_of_lists left_scale "
	select distinct	[join $left_vars ", "]
	from		($middle_sql) c
	order by	[join $left_vars ", "]
    "]

    set last_sigma [list]
    foreach t [lindex $left_scale_plain 0] { lappend last_sigma $sigma }
    lappend left_scale_plain $last_sigma


    # Add a "subtotal" (= {$user_id $sigma}) before every new ocurrence of a user_id
    set left_scale [list]
    set last_user_id 0
    foreach scale_item $left_scale_plain {
	set user_id [lindex $scale_item 0]
	if {$last_user_id != $user_id} {
	    lappend left_scale [list $user_id $sigma]
	    set last_user_id $user_id
	}
	lappend left_scale $scale_item
    }

    # ------------------------------------------------------------
    # Display the Table Header
    
    # Determine how many date rows (year, month, day, ...) we've got
    set first_cell [lindex $top_scale 0]
    set top_scale_rows [llength $first_cell]
    set left_scale_size [llength [lindex $left_scale 0]]
    
    set header ""
    for {set row 0} {$row < $top_scale_rows} { incr row } {
	
	append header "<tr class=rowtitle>\n"
	set col_l10n [lang::message::lookup "" "intranet-ganttproject.Dim_[lindex $top_vars $row]" [lindex $top_vars $row]]
	if {0 == $row} {
	    set zoom_in "<a href=[export_vars -base $this_url {top_vars {zoom "in"}}]>[im_gif "magnifier_zoom_in"]</a>\n" 
	    set zoom_out "<a href=[export_vars -base $this_url {top_vars {zoom "out"}}]>[im_gif "magifier_zoom_out"]</a>\n" 
	    set col_l10n "$zoom_in $zoom_out $col_l10n\n" 
	}
	append header "<td class=rowtitle colspan=$left_scale_size align=right>$col_l10n</td>\n"
	
	for {set col 0} {$col <= [expr [llength $top_scale]-1]} { incr col } {
	    
	    set scale_entry [lindex $top_scale $col]
	    set scale_item [lindex $scale_entry $row]
	    
	    # Skip the last line with all sigmas - doesn't sum up...
	    set all_sigmas_p 1
	    foreach e $scale_entry { if {$e != $sigma} { set all_sigmas_p 0 }	}
	    if {$all_sigmas_p} { continue }

	    
	    # Check if the previous item was of the same content
	    set prev_scale_entry [lindex $top_scale [expr $col-1]]
	    set prev_scale_item [lindex $prev_scale_entry $row]

	    # Check for the "sigma" sign. We want to display the sigma
	    # every time (disable the colspan logic)
	    if {$scale_item == $sigma} { 
		append header "\t<td class=rowtitle>$scale_item</td>\n"
		continue
	    }
	    
	    # Prev and current are same => just skip.
	    # The cell was already covered by the previous entry via "colspan"
	    if {$prev_scale_item == $scale_item} { continue }
	    
	    # This is the first entry of a new content.
	    # Look forward to check if we can issue a "colspan" command
	    set colspan 1
	    set next_col [expr $col+1]
	    while {$scale_item == [lindex [lindex $top_scale $next_col] $row]} {
		incr next_col
		incr colspan
	    }
	    append header "\t<td class=rowtitle colspan=$colspan>$scale_item</td>\n"	    
	    
	}
	append header "</tr>\n"
    }
    append html $header

    # ------------------------------------------------------------
    # Execute query and aggregate values into a Hash array

    set cnt_outer 0
    set cnt_inner 0
    db_foreach query $outer_sql {

	# Skip empty percentage entries. Improves performance...
	if {"" == $percentage} { continue }
	
	# Get all possible permutations (N out of M) from the dimension_vars
	set perms [im_report_take_all_ordered_permutations $dimension_vars]
	
	# Add the gantt hours to ALL of the variable permutations.
	# The "full permutation" (all elements of the list) corresponds
	# to the individual cell entries.
	# The "empty permutation" (no variable) corresponds to the
	# gross total of all values.
	# Permutations with less elements correspond to subtotals
	# of the values along the missing dimension. Clear?
	#
	foreach perm $perms {
	    
	    # Calculate the key for this permutation
	    # something like "$year-$month-$customer_id"
	    set key_expr "\$[join $perm "-\$"]"
	    set key [eval "set a \"$key_expr\""]
	    
	    # Sum up the values for the matrix cells
	    set sum 0
	    if {[info exists hash($key)]} { set sum $hash($key) }
	    
	    if {"" == $percentage} { set percentage 0 }
	    set sum [expr $sum + $percentage]
	    set hash($key) $sum
	    
	    incr cnt_inner
	}
	incr cnt_outer
    }

    # Skip component if there are not items to be displayed
    if {0 == $cnt_outer} { return "" }

    # ------------------------------------------------------------
    # Display the table body
    
    set ctr 0
    foreach left_entry $left_scale {
	
	# ------------------------------------------------------------
	# Check open/close logic of user's projects
	set project_pos [lsearch $left_vars "project_name_link"]
	set project_val [lindex $left_entry $project_pos]
	
	set user_pos [lsearch $left_vars "user_name_link"]
	set user_val [lindex $left_entry $user_pos]
	# A bit ugly - extract the user_id from user's URL...
	regexp {user_id\=([0-9]*)} $user_val match user_id
	
	if {$sigma != $project_val} {
	    # The current line is not the summary line (which is always shown).
	    # Start checking the open/close logic
	    
	    if {[lsearch $user_name_link_opened $user_id] < 0} { continue }
	}

	# ------------------------------------------------------------
	# Add empty line before the total sum. The total sum of percentage
	# shows the overall resource assignment and doesn't make much sense...
	set user_pos [lsearch $left_vars "user_name_link"]
	set user_val [lindex $left_entry $user_pos]
	if {$sigma == $user_val} {
	    continue
	}
	
	set class $rowclass([expr $ctr % 2])
	incr ctr
	

	# ------------------------------------------------------------
	# Start the row and show the left_scale values at the left
	append html "<tr class=$class>\n"
	set left_entry_ctr 0
	foreach val $left_entry { 
	    
	    # Special logic: Add +/- in front of User name for drill-in
	    if {"user_name_link" == [lindex $left_vars $left_entry_ctr] & $sigma == $project_val} {
		
		if {[lsearch $user_name_link_opened $user_id] < 0} {
		    set opened $user_name_link_opened
		    lappend opened $user_id
		    set open_url [export_vars -base $this_url {top_vars {user_name_link_opened $opened}}]
		    set val "<a href=$open_url>[im_gif "plus_9"]</a> $val"
		} else {
		    set opened $user_name_link_opened
		    set user_id_pos [lsearch $opened $user_id]
		    set opened [lreplace $opened $user_id_pos $user_id_pos]
		    set close_url [export_vars -base $this_url {top_vars {user_name_link_opened $opened}}]
		    set val "<a href=$close_url>[im_gif "minus_9"]</a> $val"
		} 
	    } else {
		
		# Append a spacer for better looks
		set val "[im_gif "cleardot" "" 0 9 9] $val"
	    }
	    
	    append html "<td><nobr>$val</nobr></td>\n" 
	    incr left_entry_ctr
	}


	# ------------------------------------------------------------
	# Write the left_scale values to their corresponding local 
	# variables so that we can access them easily when calculating
	# the "key".
	for {set i 0} {$i < [llength $left_vars]} {incr i} {
	    set var_name [lindex $left_vars $i]
	    set var_value [lindex $left_entry $i]
	    set $var_name $var_value
	}
	
   
	# ------------------------------------------------------------
	# Start writing out the matrix elements
	foreach top_entry $top_scale {
	    
	    # Skip the last line with all sigmas - doesn't sum up...
	    set all_sigmas_p 1
	    foreach e $top_entry { if {$e != $sigma} { set all_sigmas_p 0 }	}
	    if {$all_sigmas_p} { continue }
	    
	    # Write the top_scale values to their corresponding local 
	    # variables so that we can access them easily for $key
	    for {set i 0} {$i < [llength $top_vars]} {incr i} {
		set var_name [lindex $top_vars $i]
		set var_value [lindex $top_entry $i]
		set $var_name $var_value
	    }
	    
	    # Calculate the key for this permutation
	    # something like "$year-$month-$customer_id"
	    set key_expr_list [list]
	    foreach var_name $dimension_vars {
		set var_value [eval set a "\$$var_name"]
		if {$sigma != $var_value} { lappend key_expr_list $var_name }
	    }
	    set key_expr "\$[join $key_expr_list "-\$"]"
	    set key [eval "set a \"$key_expr\""]
	    
	    set val ""
	    if {[info exists hash($key)]} { set val $hash($key) }
	    
	    # ------------------------------------------------------------
	    # Format the percentage value for percent-arithmetics:
	    # - Sum up percentage values per day
	    # - When showing percentag per week then sum up and divide by 5 (working days)
	    # ToDo: Include vacation calendar and resource availability in
	    # the future.
	    
	    if {"" == $val} { set val 0 }

	    set period "day_of_month"
	    for {set top_idx 0} {$top_idx < [llength $top_vars]} {incr top_idx} {
		set top_var [lindex $top_vars $top_idx]
		set top_value [lindex $top_entry $top_idx]
		if {$sigma != $top_value} { set period $top_var }
	    }

	    set val_day $val
	    set val_week [expr round($val/5)]
	    set val_month [expr round($val/22)]
	    set val_quarter [expr round($val/66)]
	    set val_year [expr round($val/260)]

	    switch $period {
		"day_of_month" { set val $val_day }
		"week_of_year" { set val "$val_week" }
		"month_of_year" { set val "$val_month" }
		"quarter_of_year" { set val "$val_quarter" }
		"year" { set val "$val_year" }
		default { ad_return_complaint 1 "Bad period: $period" }
	    }

	    # ------------------------------------------------------------
	    
	    if {![regexp {[^0-9]} $val match]} {
		set color "\#000000"
		if {$val > 100} { set color "\#800000" }
		if {$val > 150} { set color "\#FF0000" }
	    }

	    if {0 == $val} { 
		set val "" 
	    } else { 
		set val "<font color=$color>$val%</font>\n"
	    }
	    
	    append html "<td>$val</td>\n"
	    
	}
	append html "</tr>\n"
    }


    # ------------------------------------------------------------
    # Show a line to open up an entire level

    # Check whether all user_ids are included in $user_name_link_opened
    set user_ids [lsort -unique [db_list user_ids "select distinct user_id from ($inner_sql) h order by user_id"]]
    set intersect [lsort -unique [set_intersection $user_name_link_opened $user_ids]]

    if {$user_ids == $intersect} {

	# All user_ids already opened - show "-" sign
	append html "<tr class=rowtitle>\n"
	set opened [list]
	set url [export_vars -base $this_url {top_vars {user_name_link_opened $opened}}]
	append html "<td class=rowtitle><a href=$url>[im_gif "minus_9"]</a></td>\n"
	append html "<td class=rowtitle colspan=[expr [llength $top_scale]+3]>&nbsp;</td></tr>\n"

    } else {

	# Not all user_ids are opened - show a "+" sign
	append html "<tr class=rowtitle>\n"
	set opened [lsort -unique [concat $user_name_link_opened $user_ids]]
	set url [export_vars -base $this_url {top_vars {user_name_link_opened $opened}}]
	append html "<td class=rowtitle><a href=$url>[im_gif "plus_9"]</a></td>\n"
	append html "<td class=rowtitle colspan=[expr [llength $top_scale]+3]>&nbsp;</td></tr>\n"

    }

    # ------------------------------------------------------------
    # Close the table

    set html "<table>\n$html\n</table>\n"

    return $html
}






# ----------------------------------------------------------------------
# GanttView to Project(s)
# ----------------------------------------------------------------------

ad_proc -public im_ganttproject_gantt_component {
    { -start_date "" }
    { -end_date "" }
    { -project_id "" }
    { -customer_id 0 }
    { -opened_projects "" }
    { -top_vars "" }
    { -return_url "" }
    { -export_var_list "" }
    { -zoom "" }
    { -auto_open 0 }
    { -max_col 10 }
    { -max_row 20 }
} {
    Gantt View

    @param start_date Hard start of reporting period. Defaults to start of first project
    @param end_date Hard end of replorting period. Defaults to end of last project
    @param project_id Id of project(s) to show. Defaults to all active projects
    @param customer_id Id of customer's projects to show
    @param user_name_link_opened List of users with details shown
} {
    set rowclass(0) "roweven"
    set rowclass(1) "rowodd"
    set sigma "&Sigma;"


    # -----------------------------------------------------------------
    # No project_id specified but customer - get all projects of this customer
    if {0 != $customer_id && "" == $project_id} {
	set project_id [db_list pids "
	select	project_id
	from	im_projects
	where	parent_id is null
		and company_id = :customer_id
		and project_status_id in ([join [im_sub_categories [im_project_status_open]] ","])
        "]
    }
    
    # No projects specified? Show the list of all active projects
    if {"" == $project_id} {
        set project_id [db_list pids "
	select	project_id
	from	im_projects
	where	parent_id is null
		and project_status_id in ([join [im_sub_categories [im_project_status_open]] ","])
        "]
    }

    # ToDo: Highlight the sub-project if we're showing the sub-project
    # of a main-project and open the GanttDiagram at the right place

    # One project specified - check parent_it to make sure we get the
    # top project.
    if {[llength $project_id] == 1} {
	set parent_id [db_string parent_id "
		select parent_id 
		from im_projects 
		where project_id = :project_id
	" -default ""]
	while {"" != $parent_id} {
	    set project_id $parent_id
	    set parent_id [db_string parent_id "
		select parent_id 
		from im_projects 
		where project_id = :project_id
	    " -default ""]
	}
    }

    # ------------------------------------------------------------
    # Start and End-Dat as min/max of selected projects.
    # Note that the sub-projects might "stick out" before and after
    # the main/parent project.
    
    if {"" == $start_date} {
	set start_date [db_string start_date "
	select	to_char(min(child.start_date), 'YYYY-MM-DD')
	from	im_projects parent,
		im_projects child
	where	parent.project_id in ([join $project_id ", "])
		and parent.parent_id is null
		and child.tree_sortkey
			between parent.tree_sortkey
			and tree_right(parent.tree_sortkey)

        "]
    }

    if {"" == $end_date} {
	set end_date [db_string end_date "
	select	to_char(max(child.end_date), 'YYYY-MM-DD')
	from	im_projects parent,
		im_projects child
	where	parent.project_id in ([join $project_id ", "])
		and parent.parent_id is null
		and child.tree_sortkey
			between parent.tree_sortkey
			and tree_right(parent.tree_sortkey)
        "]
    }

    if {"" == $end_date} {
	set end_date [db_string now "select now()::date"]
    } else {
	set end_date [db_string end_date "select to_char(:end_date::date+1, 'YYYY-MM-DD')"]
#	set end_date [ clock scan $end_date ]
#	set end_date [ clock scan {+1 day} -base $end_date ]
#	set end_date [ clock format "$end_date" -format %Y-%m-%d ]
    }

    if {"" == $start_date} {
	set start_date [db_string start_date "
	select	to_char(min(child.start_date), 'YYYY-MM-DD')
	from	im_projects parent,
		im_projects child
	where	parent.project_id in ([join $project_id ", "])
		and parent.parent_id is null
		and child.tree_sortkey
			between parent.tree_sortkey
			and tree_right(parent.tree_sortkey)
        "]
    }

    # -----------------------------------------------------------------
    # Adaptive behaviour - limit the size of the component to a summary
    # suitable for the left/right columns of a project.
    if {$auto_open || "" == $top_vars} {

	set duration_days [db_string dur "
		select to_date(:end_date, 'YYYY-MM-DD') - to_date(:start_date, 'YYYY-MM-DD')
	"]
	if {"" == $duration_days} { set duration_days 0 }
	if {$duration_days < 0} { set duration_days 0 }

	set duration_weeks [expr $duration_days / 7]
	set duration_months [expr $duration_days / 30]
	set duration_quarters [expr $duration_days / 91]
	set duration_years [expr $duration_days / 365]

	set days_too_long [expr $duration_days > $max_col]
	set weeks_too_long [expr $duration_weeks > $max_col]
	set months_too_long [expr $duration_months > $max_col]
	set quarters_too_long [expr $duration_quarters > $max_col]

	set top_vars "week_of_year day_of_month"
	if {$days_too_long} { set top_vars "month_of_year week_of_year" }
	if {$weeks_too_long} { set top_vars "month_of_year" }
	if {$months_too_long} { set top_vars "year quarter_of_year" }
	if {$quarters_too_long} { set top_vars "year quarter_of_year" }
    }

    set top_vars [im_ganttproject_zoom_top_vars -zoom $zoom -top_vars $top_vars]

    # Adaptive behaviour - Open up the first level of projects
    # unless that's more then max_cols
    if {$auto_open} {
	set opened_projects $project_id
    }

    # ------------------------------------------------------------
    # Define Dimensions
    
    set left_vars [list project_id]

    # The complete set of dimensions - used as the key for
    # the "cell" hash. Subtotals are calculated by dropping on
    # or more of these dimensions
    set dimension_vars [concat $top_vars $left_vars]


    # ------------------------------------------------------------
    # URLs to different parts of the system

    set company_url "/intranet/companies/view?company_id="
    set project_url "/intranet/projects/view?project_id="
    set user_url "/intranet/users/view?user_id="
    set this_url [export_vars -base "/intranet-ganttproject/gantt-view-cube" {start_date end_date left_vars customer_id} ]
    foreach pid $project_id { append this_url "&project_id=$pid" }


    # ------------------------------------------------------------
    # Conditional SQL Where-Clause
    #
    
    set criteria [list]
    
    if {"" != $customer_id && 0 != $customer_id} {
	lappend criteria "parent.company_id = :customer_id"
    }
    
    if {"" != $project_id && 0 != $project_id} {
	lappend criteria "parent.project_id in ([join $project_id ", "])"
    }
    
    set where_clause [join $criteria " and\n\t\t\t"]
    if { ![empty_string_p $where_clause] } {
	set where_clause " and $where_clause"
    }
    

    # ------------------------------------------------------------
    # Define the report - SQL, counters, headers and footers 
    #
    
    # Inner - Try to be as selective as possible for the relevant data from the fact table.
    set inner_sql "
		select
			1 as days,
			tree_level(child.tree_sortkey) - tree_level(parent.tree_sortkey) as level,
		        child.project_id,
		        child.project_name,
			child.project_nr,
			child.tree_sortkey,
			d.d
		from
		        im_projects parent,
		        im_projects child,
		        ( select im_day_enumerator as d
		          from im_day_enumerator (
				to_date(:start_date, 'YYYY-MM-DD'), 
				to_date(:end_date, 'YYYY-MM-DD')
			) ) d
		where
			parent.project_status_id in ([join [im_sub_categories [im_project_status_open]] ","])
		        and parent.parent_id is null
		        and child.tree_sortkey 
				between parent.tree_sortkey 
				and tree_right(parent.tree_sortkey)
		        and d.d 
				between child.start_date 
				and child.end_date
			$where_clause
    "


    # Aggregate additional/important fields to the fact table.
    set middle_sql "
	select
		h.*,
		'<a href=${project_url}'||project_id||'>'||project_name||'</a>' as project_name_link,
		to_char(h.d, 'YYYY') as year,
		'<!--' || to_char(h.d, 'YYYY') || '-->Q' || to_char(h.d, 'Q') as quarter_of_year,
		'<!--' || to_char(h.d, 'YYYY-MM') || '-->' || to_char(h.d, 'Mon') as month_of_year,
		'<!--' || to_char(h.d, 'YYYY-MM') || '-->W' || to_char(h.d, 'IW') as week_of_year,
		'<!--' || to_char(h.d, 'YYYY-MM') || '-->' || to_char(h.d, 'DD') as day_of_month
	from	($inner_sql) h
    "

    set outer_sql "
	select
		sum(h.days) as days,
		[join $dimension_vars ",\n\t"]
	from
		($middle_sql) h
	group by
		[join $dimension_vars ",\n\t"]
    "

    # Get the level of task indenting in the project
    set max_level [db_string max_depth "select max(level) from ($middle_sql) c" -default 0]


    # ------------------------------------------------------------
    # Create upper date dimension


    # Top scale is a list of lists such as {{2006 01} {2006 02} ...}
    # The last element of the list the grand total sum.
    set top_scale [db_list_of_lists top_scale "
	select distinct	[join $top_vars ", "]
	from		($middle_sql) c
	order by	[join $top_vars ", "]
    "]

    # ------------------------------------------------------------
    # Display the Table Header
    
    # Determine how many date rows (year, month, day, ...) we've got
    set first_cell [lindex $top_scale 0]
    set top_scale_rows [llength $first_cell]
    set left_scale_size $max_level
    set header_class "rowtitle"
    set header ""
    for {set row 0} {$row < $top_scale_rows} { incr row } {
	
	append header "<tr class=$header_class>\n"
	set col_l10n [lang::message::lookup "" "intranet-ganttproject.Dim_[lindex $top_vars $row]" [lindex $top_vars $row]]
	if {0 == $row} {
	    set zoom_in "<a href=[export_vars -base $this_url {top_vars opened_projects {zoom "in"}}]>[im_gif "magnifier_zoom_in"]</a>\n" 
	    set zoom_out "<a href=[export_vars -base $this_url {top_vars opened_projects {zoom "out"}}]>[im_gif "magifier_zoom_out"]</a>\n" 
	    set col_l10n "$zoom_in $zoom_out $col_l10n\n" 
	}
	append header "<td class=$header_class colspan=[expr $max_level+2] align=right>$col_l10n</td>\n"
	
	for {set col 0} {$col <= [expr [llength $top_scale]-1]} { incr col } {
	    
	    set scale_entry [lindex $top_scale $col]
	    set scale_item [lindex $scale_entry $row]
	    
	    # Skip the last line with all sigmas - doesn't sum up...
	    set all_sigmas_p 1
	    foreach e $scale_entry { if {$e != $sigma} { set all_sigmas_p 0 }	}
	    if {$all_sigmas_p} { continue }

	    
	    # Check if the previous item was of the same content
	    set prev_scale_entry [lindex $top_scale [expr $col-1]]
	    set prev_scale_item [lindex $prev_scale_entry $row]

	    # Check for the "sigma" sign. We want to display the sigma
	    # every time (disable the colspan logic)
	    if {$scale_item == $sigma} { 
		append header "\t<td class=$header_class>$scale_item</td>\n"
		continue
	    }
	    
	    # Prev and current are same => just skip.
	    # The cell was already covered by the previous entry via "colspan"
	    if {$prev_scale_item == $scale_item} { continue }
	    
	    # This is the first entry of a new content.
	    # Look forward to check if we can issue a "colspan" command
	    set colspan 1
	    set next_col [expr $col+1]
	    while {$scale_item == [lindex [lindex $top_scale $next_col] $row]} {
		incr next_col
		incr colspan
	    }
	    append header "\t<td class=$header_class colspan=$colspan>$scale_item</td>\n"	    
	    
	}
	append header "</tr>\n"
    }
    set html $header


    # ------------------------------------------------------------
    # Execute query and aggregate values into a Hash array

    set cnt_outer 0
    set cnt_inner 0
    db_foreach query $outer_sql {

	# Get all possible permutations (N out of M) from the dimension_vars
	set perms [im_report_take_all_ordered_permutations $dimension_vars]
	
	# Add the gantt hours to ALL of the variable permutations.
	# The "full permutation" (all elements of the list) corresponds
	# to the individual cell entries.
	# The "empty permutation" (no variable) corresponds to the
	# gross total of all values.
	# Permutations with less elements correspond to subtotals
	# of the values along the missing dimension. Clear?
	#
	foreach perm $perms {
	    
	    # Calculate the key for this permutation
	    # something like "$year-$month-$customer_id"
	    set key_expr "\$[join $perm "-\$"]"
	    set key [eval "set a \"$key_expr\""]
	    
	    # Sum up the values for the matrix cells
	    set sum 0
	    if {[info exists hash($key)]} { set sum $hash($key) }
	    
	    if {"" == $days} { set days 0 }
	    set sum [expr $sum + $days]
	    set hash($key) $sum
	    
	    incr cnt_inner
	}
	incr cnt_outer
    }

    # Skip component if there are not items to be displayed
    if {0 == $cnt_outer} { return "" }


    # ------------------------------------------------------------
    # Display the table body
    
    set left_sql "
		select
		        child.project_id,
		        child.project_name,
			child.parent_id,
			tree_level(child.tree_sortkey) - tree_level(parent.tree_sortkey) as level
		from
		        im_projects parent,
		        im_projects child
		where
			parent.project_status_id in ([join [im_sub_categories [im_project_status_open]] ","])
		        and parent.parent_id is null
		        and child.tree_sortkey 
				between parent.tree_sortkey 
				and tree_right(parent.tree_sortkey)
			$where_clause
    "
    db_foreach left $left_sql {

	# Store the project_id - project_name relationship
	set project_name_hash($project_id) "<a href=\"$project_url$project_id\">$project_name</a>"

	# Determine the number of children per project
	if {![info exists child_count_hash($project_id)]} { set child_count_hash($project_id) 0 }
	if {![info exists child_count_hash($parent_id)]} { set child_count_hash($parent_id) 0 }
	set child_count $child_count_hash($parent_id)
	set child_count_hash($parent_id) [expr $child_count+1]
	
	# Create a list of projects for each level for fast opening
	set level_list [list]
	if {[info exists level_lists($level)]} { set level_list $level_lists($level) }
	lappend level_list $project_id
	set level_lists($level) $level_list
    }
    
    # ------------------------------------------------------------
    # Display the table body
    
    set left_sql "
	select distinct
		c.project_id,
		c.project_name,	
		c.level,
		c.tree_sortkey
	from
		($middle_sql) c
	order by
		c.tree_sortkey
    "

    set ctr 0
    set project_name_hash($sigma) "sigma"
    set project_name_hash("") "empty"
    set project_name_hash() "empty"
    set project_hierarchy(0) 0

    db_foreach left $left_sql {

	# Store/overwrite the position of project_id in the hierarchy
	set project_hierarchy($level) $project_id
	ns_log Notice "im_ganttproject_gantt_component: project_hierarchy($level) = $project_id"

	# Determine the project-"path" from the top project to the current level
	set project_path [list]
	set open_p 1
	for {set i 0} {$i < $level} {incr i} { 
	    if {[info exists project_hierarchy($i)]} {
		lappend project_path $project_hierarchy($i) 
		if {[lsearch $opened_projects $project_hierarchy($i)] < 0} { set open_p 0 }
	    }
	}
	if {!$open_p} { continue }
	lappend project_path $project_id

	set org_project_id $project_id
	set class $rowclass([expr $ctr % 2])
	incr ctr
	

	# Start the row and show the left_scale values at the left
	append html "<tr class=$class>\n"

	set left_entry_ctr 0
	foreach project_id $project_path { 

	    set project_name $project_name_hash($project_id)
	    set left_entry_ctr_pp [expr $left_entry_ctr+1]
	    set left_entry_ctr_mm [expr $left_entry_ctr-1]

	    set open_p [expr [lsearch $opened_projects $project_id] >= 0]
	    if {$open_p} {
		set opened $opened_projects
		set project_id_pos [lsearch $opened $project_id]
		set opened [lreplace $opened $project_id_pos $project_id_pos]
		set url [export_vars -base $this_url {top_vars {opened_projects $opened}}]
		set gif [im_gif "minus_9"]
	    } else {
		set opened $opened_projects
		lappend opened $project_id
		set url [export_vars -base $this_url {top_vars {opened_projects $opened}}]
		set gif [im_gif "plus_9"]
	    }
	    
	    if {$child_count_hash($project_id) == 0} { 
		set url ""
		set gif [im_gif "cleardot" "" 0 9 9]
	    }
	    
	    set col_val($left_entry_ctr_mm) ""
	    set col_val($left_entry_ctr) "<a href=$url>$gif</a>"
	    set col_val($left_entry_ctr_pp) $project_name
	    
	    set col_span($left_entry_ctr_mm) 1
	    set col_span($left_entry_ctr) 1
	    set col_span($left_entry_ctr_pp) [expr $max_level+1-$left_entry_ctr]

	    incr left_entry_ctr
	}


	set left_entry_ctr 0
	foreach project_id $project_path { 
	    append html "<td colspan=$col_span($left_entry_ctr)><nobr>$col_val($left_entry_ctr)</nobr></td>\n" 
	    incr left_entry_ctr
	}
	append html "<td colspan=$col_span($left_entry_ctr)><nobr>$col_val($left_entry_ctr)</nobr></td>\n" 

	
   
	# ------------------------------------------------------------
	# Start writing out the matrix elements
	set project_id $org_project_id
	set last_days 0
	set last_colspan 0

	for {set top_entry_idx 0} {$top_entry_idx < [llength $top_scale]} {incr top_entry_idx} {

	    # --------------------------------------------------
	    # Get the "next_days" (=days of the next table column)
	    set top_entry_next [lindex $top_scale [expr $top_entry_idx+1]]
	    for {set i 0} {$i < [llength $top_vars]} {incr i} {
		set var_name [lindex $top_vars $i]
		set var_value [lindex $top_entry_next $i]
		set $var_name $var_value
	    }
	    set key_expr_list [list]
	    foreach var_name $dimension_vars {
		set var_value [eval set a "\$$var_name"]
		if {$sigma != $var_value} { lappend key_expr_list $var_name }
	    }
	    set key_expr "\$[join $key_expr_list "-\$"]"
	    set key [eval "set a \"$key_expr\""]
	    set next_days ""
	    if {[info exists hash($key)]} { set next_days $hash($key) }
	    if {"" == $next_days} { set next_days 0 }
	    if {1 < $next_days} { set next_days 1 }




	    # --------------------------------------------------
	    set top_entry [lindex $top_scale $top_entry_idx]
	    
	    # Skip the last line with all sigmas - doesn't sum up...
	    set all_sigmas_p 1
	    foreach e $top_entry { if {$e != $sigma} { set all_sigmas_p 0 } }
	    if {$all_sigmas_p} { continue }

	    # Write the top_scale values to their corresponding local 
	    # variables so that we can access them easily for $key
	    for {set i 0} {$i < [llength $top_vars]} {incr i} {
		set var_name [lindex $top_vars $i]
		set var_value [lindex $top_entry $i]
		set $var_name $var_value
	    }
	    
	    # Calculate the key for this permutation
	    # something like "$year-$month-$customer_id"
	    set key_expr_list [list]
	    foreach var_name $dimension_vars {
		set var_value [eval set a "\$$var_name"]
		if {$sigma != $var_value} { lappend key_expr_list $var_name }
	    }
	    set key_expr "\$[join $key_expr_list "-\$"]"
	    set key [eval "set a \"$key_expr\""]
	    set days ""
	    if {[info exists hash($key)]} { set days $hash($key) }
	    if {"" == $days} { set days 0 }
	    if {1 < $days} { set days 1 }


	    # --------------------------------------------------
	    # Determine how to render the combination of last_days - days $next_days

	    set cell_html ""
	    switch "$last_days$days$next_days" {
		"000" { set cell_html "<td></td>\n" }
		"001" { set cell_html "<td></td>\n" }
		"010" { 
		    set cell_html "<td><img src=\"/intranet-ganttproject/images/gant_bar_single_15.gif\"></td>\n"

		    set cell_html "<td>
			  <table width='100%' border=1 cellspacing=0 cellpadding=0 bordercolor=black bgcolor='\#8CB6CE'>
			    <tr height=11><td></td></tr>
			  </table>
		    </td>\n"

		}
		"011" { 
		    # Start of a new bar.
		    # Do nothing - delayed until "110"
		    set cell_html ""
		    set last_colspan 1
		}
		"100" { set cell_html "<td></td>\n" }
		"101" { set cell_html "<td></td>\n" }
		"110" { 
		    # Write out the entire cell with $last_colspan
		    incr last_colspan
		    set cell_html "
			<td colspan=$last_colspan>
			  <table width='100%' border=1 cellspacing=0 cellpadding=0 bordercolor=black bgcolor='\#8CB6CE'>
			    <tr height=11><td></td></tr>
			  </table>
			</td>\n"
		}
		"111" { incr last_colspan }
	    }

	    append html $cell_html
	    set last_days $days

	    
	}
	append html "</tr>\n"
    }


    # ------------------------------------------------------------
    # Show a line to open up an entire level

    append html "<tr class=$header_class>\n"
    set level_list [list]
    for {set col 0} {$col < $max_level} {incr col} {

	set local_level_list [list]
	if {[info exists level_lists($col)]} { set local_level_list $level_lists($col) }
	set level_list [lsort -unique [concat $level_list $local_level_list]]

	# Check whether all project_ids are included in $level_list
	set intersect [lsort -unique [set_intersection $opened_projects $level_list]]
	if {$level_list == $intersect} {

	    # Everything opened - display a "-" button
	    set opened [set_difference $opened_projects $local_level_list]
	    set url [export_vars -base $this_url {top_vars {opened_projects $opened}}]
	    append html "<td class=$header_class><a href=$url>[im_gif "minus_9"]</a></td>\n"

	} else {

	    set opened [lsort -unique [concat $opened_projects $level_list]]
	    set url [export_vars -base $this_url {top_vars {opened_projects $opened}}]
	    append html "<td class=$header_class><a href=$url>[im_gif "plus_9"]</a></td>\n"

	}


    }
    append html "<td class=$header_class colspan=[expr [llength $top_scale]+2]>&nbsp;</td></tr>\n"

    return "<table>\n$html\n</table>\n"
}


ad_proc -public im_ganttproject_zoom_top_vars {
    -zoom
    -top_vars
} {
    Zooms in/out of top_vars
} {
    if {"in" == $zoom} {
	# check for most detailed variable in top_vars
	if {[lsearch $top_vars "day_of_month"] >= 0} { return {week_of_year day_of_month} }
	if {[lsearch $top_vars "week_of_year"] >= 0} { return {week_of_year day_of_month} }
	if {[lsearch $top_vars "month_of_year"] >= 0} { return {month_of_year week_of_year} }
	if {[lsearch $top_vars "quarter_of_year"] >= 0} { return {quarter_of_year month_of_year} }
	if {[lsearch $top_vars "year"] >= 0} { return {year quarter_of_year} }
    }

    if {"out" == $zoom} {
	# check for most coarse-grain variable in top_vars
	if {[lsearch $top_vars "year"] >= 0} { return {year quarter_of_year} }
	if {[lsearch $top_vars "quarter_of_year"] >= 0} { return {year quarter_of_year} }
	if {[lsearch $top_vars "month_of_year"] >= 0} { return {quarter_of_year month_of_year} }
	if {[lsearch $top_vars "week_of_year"] >= 0} { return {month_of_year week_of_year} }
	if {[lsearch $top_vars "day_of_month"] >= 0} { return {week_of_year day_of_month} }
    }

    return $top_vars
}

ad_proc -public im_ganttproject_add_import {
    object_type
    name
} {
    set column_name "xml_$name"
    set field_present_command "attribute::exists_p $object_type $column_name"
    set field_present [util_memoize $field_present_command]
    if {!$field_present} {
	attribute::add  -min_n_values 0 -max_n_values 1 "$object_type" "string" $column_name $column_name
	ns_write [ns_cache flush util_memoize $field_present_command]
    }		
}






# ---------------------------------------------------------------
# Display Procedure for Resource Planning
# ---------------------------------------------------------------


ad_proc -public im_ganttproject_resource_planning_cell {
    percentage
} {
    Takes a percentage value and returns a formatted HTML ready to be
    displayed as part of a cell
} {
    if {0 == $percentage || "" == $percentage} { return "" }

    if {![string is double $percentage]} { return $percentage }

    # Color selection
    set color ""
    if {$percentage > 0} { set color "bluedot" }
    if {$percentage > 100} { set color "800000" }
    if {$percentage > 180} { set color "FF0000" }

    set color "bluedot"    

    set p [expr int((1.0 * $percentage) / 10.0)]
    set result [im_gif $color "$percentage" 0 10 $p]
    return $result
}


# ---------------------------------------------------------------
# Auxillary procedures for Resource Report
# ---------------------------------------------------------------


ad_proc -public im_date_julian_to_components { julian_date } {
    Takes a Julian data and returns an array of its components:
    Year, MonthOfYear, DayOfMonth, WeekOfYear, Quarter
} {
    set ansi [dt_julian_to_ansi $julian_date]
    regexp {(....)-(..)-(..)} $ansi match year month_of_year day_of_month
    set month_of_year [string trim $month_of_year 0]
    set first_year_julian [dt_ansi_to_julian $year 1 1]
    set day_of_year [expr $julian_date - $first_year_julian + 1]
    set quarter_of_year [expr 1 + int(($month_of_year-1) / 3)]

    set week_of_year [util_memoize [list db_string dow "select to_char(to_date($julian_date, 'J'),'IW')"]]
    set day_of_week [util_memoize [list db_string dow "select extract(dow from to_date($julian_date, 'J'))"]]
    if {0 == $day_of_week} { set day_of_week 7 }
   
    return [list year $year \
		month_of_year $month_of_year \
		day_of_month $day_of_month \
		week_of_year $week_of_year \
		quarter_of_year $quarter_of_year \
		day_of_year $day_of_year \
		day_of_week $day_of_week \
    ]
}


ad_proc -public im_date_julian_to_week_julian { julian_date } {
    Takes a Julian data and returns the julian date of the week's day "1" (=Monday)
} {
    array set week_info [im_date_julian_to_components $julian_date]
    set result [expr $julian_date - $week_info(day_of_week)]
}



ad_proc -public im_date_components_to_julian { top_vars top_entry} {
    Takes an entry from top_vars/top_entry and tries
    to figure out the julian date from this
} {
    set ctr 0
    foreach var $top_vars {
	set val [lindex $top_entry $ctr]
	set $var $val
	incr ctr
    }

    set julian 0

    # Try to calculate the current data from top dimension
    switch $top_vars {
	"year week_of_year day_of_week" {
	    catch {
		set first_of_year_julian [dt_ansi_to_julian $year 1 1]
		set dow_first_of_year_julian [db_string dow "select to_char('$year-01-07'::date, 'D')"]
		set start_first_week_julian [expr $first_of_year_julian - $dow_first_of_year_julian]
		set julian [expr $start_first_week_julian + 7 * $week_of_year + $day_of_week]
	    }
	}
	"year week_of_year" {
	    catch {
		set first_of_year_julian [dt_ansi_to_julian $year 1 1]
		set dow_first_of_year_julian [db_string dow "select to_char('$year-01-07'::date, 'D')"]
		set start_first_week_julian [expr $first_of_year_julian - $dow_first_of_year_julian]
		set julian [expr $start_first_week_julian + 7 * $week_of_year]
	    }
	}
	"year month_of_year day_of_month" {
	    catch {
		if {1 == [string length $month_of_year]} { set month_of_year "0$month_of_year" }
		if {1 == [string length $day_of_month]} { set day_of_month "0$day_of_month" }
		set julian [db_string jul "select to_char('$year-$month_of_year-$day_of_month'::date,'J')"]
	    }
	}
	"year month_of_year" {
	    catch {
		if {1 == [string length $month_of_year]} { set month_of_year "0$month_of_year" }
		set julian [db_string jul "select to_char('$year-$month_of_year-01'::date,'J')"]
	    }
	}
    }

    if {0 == $julian} { 
	ad_return_complaint 1 "$top_vars<br>$top_entry"
	ad_return_complaint 1 "Unable to calculate data from date dimension: '$top_vars'" 
    }

    ns_log Notice "im_date_components_to_julian: $julian, top_vars=$top_vars, top_entry=$top_entry"
    return $julian
}



# ---------------------------------------------------------------
# Resource Planning Report
# ---------------------------------------------------------------


ad_proc -public im_ganttproject_resource_planning {
    { -start_date "" }
    { -end_date "" }
    { -show_all_employees_p "" }
    { -top_vars "year week_or_year day" }
    { -left_vars "cell" }
    { -project_id "" }
    { -user_id "" }
    { -customer_id 0 }
    { -return_url "" }
    { -export_var_list "" }
    { -zoom "" }
    { -auto_open 0 }
    { -max_col 8 }
    { -max_row 20 }
} {
    Gantt Resource "Cube"

    @param start_date Hard start of reporting period. Defaults to start of first project
    @param end_date Hard end of replorting period. Defaults to end of last project
    @param project_id Id of project(s) to show. Defaults to all active projects
    @param customer_id Id of customer's projects to show
} {
    set rowclass(0) "roweven"
    set rowclass(1) "rowodd"
    set sigma "&Sigma;"
    set page_url "/intranet-ganttproject/gantt-resources-planning"
    set current_user_id [ad_get_user_id]
    set return_url [im_url_with_query]

    set project_base_url "/intranet/projects/view"
    set user_base_url "/intranet/users/view"

    # The list of users/projects opened already
    set user_name_link_opened {}

    # Determine what aggregates to calculate
    set calc_day_p 0
    set calc_week_p 0
    set calc_month_p 0
    set calc_quarter_p 0
    switch $top_vars {
        "year week_of_year day_of_week" { set calc_day_p 1 }
        "year month_of_year day_of_month" { set calc_day_p 1 }
        "year week_of_year" { set calc_week_p 1 }
        "year month_of_year" { set calc_month_p 1 }
        "year quarter_of_year" { set calc_quarter_p 1 }
    }


    if {0 != $customer_id && "" == $project_id} {
	set project_id [db_list pids "
	select	project_id
	from	im_projects
	where	parent_id is null
		and company_id = :customer_id
        "]
    }

    db_1row date_calc "
	select	to_char(:start_date::date, 'J') as start_date_julian,
		to_char(:end_date::date, 'J') as end_date_julian
    "

    # ------------------------------------------------------------
    # URLs to different parts of the system

    set collapse_url "/intranet/biz-object-tree-open-close"
    set company_url "/intranet/companies/view?company_id="
    set project_url "/intranet/projects/view?project_id="
    set user_url "/intranet/users/view?user_id="
    set this_url [export_vars -base $page_url {start_date end_date customer_id} ]
    foreach pid $project_id { append this_url "&project_id=$pid" }

    # ------------------------------------------------------------
    # Conditional SQL Where-Clause
    #
    
    set criteria [list]
    if {"" != $customer_id && 0 != $customer_id} { lappend criteria "parent.company_id = :customer_id" }
    if {"" != $project_id && 0 != $project_id} { lappend criteria "parent.project_id in ([join $project_id ", "])" }
    if {"" != $user_id && 0 != $user_id} { lappend criteria "u.user_id in ([join $user_id ","])" }

    set where_clause [join $criteria " and\n\t\t\t"]
    if { ![empty_string_p $where_clause] } {
	set where_clause " and $where_clause"
    }


    # ------------------------------------------------------------
    # Collapse lines in the report - store results in a Hash
    #
    set collapse_sql "
		select	object_id,
			open_p
		from	im_biz_object_tree_status
		where	user_id = :current_user_id and
			page_url = :page_url
    "
    db_foreach collapse $collapse_sql {
	set collapse_hash($object_id) $open_p
    }


    # ------------------------------------------------------------
    # Weekends
    #
    for {set i $start_date_julian} {$i <= $end_date_julian} {incr i} {
	array unset date_comps
	array set date_comps [im_date_julian_to_components $i]
	set dow $date_comps(day_of_week)
	if {0 == $dow || 6 == $dow || 7 == $dow} { 
	    set key $i
	    set weekend_hash($key) 5
	}
    }


    # ------------------------------------------------------------
    # Absences - Determine when the user is away
    #
    set absences_sql "
	-- Direct absences for a user within the period
	select
		owner_id,
		to_char(start_date,'J') as absence_start_date_julian,
		to_char(end_date,'J') as absence_end_date_julian,
		absence_type_id
	from 
		im_user_absences
	where 
		group_id is null and
		start_date <= to_date(:end_date, 'YYYY-MM-DD') and
		end_date   >= to_date(:start_date, 'YYYY-MM-DD')
    UNION
	-- Absences via groups - Check if the user is a member of group_id
	select
		mm.member_id as owner_id,
		to_char(start_date,'J') as absence_start_date_julian,
		to_char(end_date,'J') as absence_end_date_julian,
		absence_type_id
	from 
		im_user_absences a,
		group_distinct_member_map mm
	where 
		a.group_id = mm.group_id and
		start_date <= to_date(:end_date, 'YYYY-MM-DD') and
		end_date   >= to_date(:start_date, 'YYYY-MM-DD')
    "
    db_foreach absences $absences_sql {
	for {set i $absence_start_date_julian} {$i <= $absence_end_date_julian} {incr i} {

	    # Aggregate per day
	    if {$calc_day_p} {
		set key "$i-$owner_id"
		set val ""
		if {[info exists absences_hash($key)]} { set val $absences_hash($key) }
		append val [expr $absence_type_id - 5000]
		set absences_hash($key) $val
	    }

	    # Aggregate per week, skip weekends
	    if {$calc_week_p && ![info exists weekend_hash($i)]} {
		set week_julian [util_memoize [list im_date_julian_to_week_julian $i]]
		set key "$week_julian-$owner_id"
		set val ""
		if {[info exists absences_hash($key)]} { set val $absences_hash($key) }
		append val [expr $absence_type_id - 5000]
		set absences_hash($key) $val
	    }

	}
    }

    # ------------------------------------------------------------
    # Projects - determine project & task assignments at the lowest level.
    #
    set percentage_sql "
		select
			child.project_id,
			child.project_name,
			child.parent_id,
			parent.project_id as main_project_id,
			r.object_id_two as user_id,
			im_name_from_user_id(r.object_id_two) as user_name,
			trunc(m.percentage) as percentage,
			child.start_date::date as child_start_date,
			to_char(child.start_date, 'J') as child_start_date_julian,
			child.end_date::date as child_end_date,
			to_char(child.end_date, 'J') as child_end_date_julian,
			tree_level(child.tree_sortkey) - tree_level(parent.tree_sortkey) as object_level,
			child.tree_sortkey
		from
			im_projects parent,
			im_projects child,
			acs_rels r,
			im_biz_object_members m
		where
			parent.project_status_id not in ([join [im_sub_categories [im_project_status_closed]] ","])
			and parent.parent_id is null
			and parent.end_date >= to_date(:start_date, 'YYYY-MM-DD')
			and parent.start_date <= to_date(:end_date, 'YYYY-MM-DD')
			and child.tree_sortkey
				between parent.tree_sortkey
				and tree_right(parent.tree_sortkey)
			and r.rel_id = m.rel_id
			and r.object_id_one = child.project_id
			and m.percentage is not null
			$where_clause
    "


    # ------------------------------------------------------------
    # Main Projects x Users:
    # Return all main projects where a user is assigned in one of the sub-projects
    #

    set show_all_employees_sql ""
    if {1 == $show_all_employees_p} {
	set show_all_employees_sql "
	UNION
		select
			0::integer as main_project_id,
			0::text as main_project_name,
			p.person_id as user_id,
			im_name_from_user_id(p.person_id) as user_name
		from
			persons p,
			group_distinct_member_map gdmm
		where
			gdmm.member_id = p.person_id and
			gdmm.group_id = [im_employee_group_id]
	"
    }

    set main_projects_sql "
	select distinct
		main_project_id,
		main_project_name,
		user_id,
		user_name
	from
		(select
			parent.project_id as main_project_id,
			parent.project_name as main_project_name,
			r.object_id_two as user_id,
			im_name_from_user_id(r.object_id_two) as user_name
		from
			im_projects parent,
			im_projects child,
			acs_rels r,
			im_biz_object_members m
		where
			parent.project_status_id not in ([join [im_sub_categories [im_project_status_closed]] ","])
			and parent.parent_id is null
			and parent.end_date >= to_date(:start_date, 'YYYY-MM-DD')
			and parent.start_date <= to_date(:end_date, 'YYYY-MM-DD')
			and child.tree_sortkey
				between parent.tree_sortkey
				and tree_right(parent.tree_sortkey)
			and r.rel_id = m.rel_id
			and r.object_id_one = child.project_id
			and m.percentage is not null
			$where_clause
		$show_all_employees_sql
		) t
	order by
		user_name,
		main_project_id
    "
    db_foreach main_projects $main_projects_sql {
	set key "$user_id-$main_project_id"
	set member_of_main_project_hash($key) 1
	set object_name_hash($user_id) $user_name
	set object_name_hash($main_project_id) $main_project_name
	set has_children_hash($user_id) 1
	set indent_hash($main_project_id) 1
	set object_type_hash($main_project_id) "im_project"
	set object_type_hash($user_id) "person"
    }


    # ------------------------------------------------------------------
    # Calculate the hierarchy.
    # We have to go through all main-projects that have children with
    # assignments, and then we have to go through all of their children
    # in order to get a complete hierarchy.
    #

    set hierarchy_sql "
	select
		parent.project_id as parent_project_id,
		child.project_id,
		child.parent_id,
		child.tree_sortkey,
		child.project_name,
		child.project_nr,
		child.tree_sortkey,
		tree_level(child.tree_sortkey) - tree_level(parent.tree_sortkey) as tree_level,
		o.object_type
	from
		im_projects parent,
		im_projects child,
		acs_objects o
	where
		parent.project_status_id not in ([join [im_sub_categories [im_project_status_closed]] ","])
		and parent.parent_id is null
		and parent.tree_sortkey in (
			select	tree_ancestor_key(t.tree_sortkey,1) as tree_level
			from	($percentage_sql) t
		)
		and child.project_id = o.object_id
		and child.tree_sortkey
			between parent.tree_sortkey
			and tree_right(parent.tree_sortkey)
	order by
		parent.project_id,
		child.tree_sortkey
    "

    set empty ""
    set name_hash($empty) ""
    set parent_project_id 0
    set old_parent_project_id 0
    set hierarchy_lol {}
    db_foreach project_hierarchy $hierarchy_sql {

	ns_log Notice "gantt-resources-planning: parent=$parent_project_id, child=$project_id, tree_level=$tree_level"
	# Store the list of sub-projects into the hash once the main project changes
	if {$old_parent_project_id != $parent_project_id} {
	    set main_project_hierarchy_hash($old_parent_project_id) $hierarchy_lol
	    set hierarchy_lol {}
	    set old_parent_project_id $parent_project_id
	}

	# Store project hierarchy information into hashes
	set parent_hash($project_id) $parent_id
	set has_children_hash($parent_id) 1
	set sortkey_hash($tree_sortkey) $project_id
	set name_hash($project_id) $project_name
	set indent_hash($project_id) [expr $tree_level + 1]
	set object_name_hash($project_id) $project_name
	set object_type_hash($project_id) $object_type

	# Determine the project path that leads to the current sub-project
	# and aggregate the current assignment information to all parents.
	set hierarchy_row {}
	set level $tree_level
	set pid $project_id
	while {$level >= 0} {
	    lappend hierarchy_row $pid
	    set pid $parent_hash($pid)
	    incr level -1
	}

	lappend hierarchy_lol [list $project_id $project_name $tree_level [f::reverse $hierarchy_row] $tree_sortkey]
    }
    # Save the list of sub-projects of the last main project (see above in the loop)
    set main_project_hierarchy_hash($parent_project_id) $hierarchy_lol


    # ------------------------------------------------------------------
    # Calculate the left scale.
    #
    # The scale is composed by three different parts:
    #
    # - The user
    # - The outer "main_projects_sql" selects out users and their main_projects
    #   in which they are assigned with some percentage. All elements of this
    #   SQL are shown always.
    # - The inner "project_lol" look shows the _entire_ tree of sub-projects and
    #   tasks for each main_project. That's necessary, because no SQL could show
    #   us the 
    #
    # The scale starts with the "user" dimension, followed by the 
    # main_projects to which the user is a member. Then follows the
    # full hierarchy of the main_project.
    #
    set left_scale {}
    set old_user_id 0
    db_foreach left_scale_users $main_projects_sql {

	# ----------------------------------------------------------------------
	# Determine the user and write out the first line without projects

	# Add a line without project, only for the user
	if {$user_id != $old_user_id} {
	    # remember the type of the object
	    set otype_hash($user_id) "person"
	    # append the user_id to the left_scale
	    lappend left_scale [list $user_id ""]
	    # Remember that we have already processed this user
	    set old_user_id $user_id
	}

	# ----------------------------------------------------------------------
	# Write out the project-tree for the main-projects.

	# Make sure that the user is assigned somewhere in the main project
	# or otherwise skip the entire main_project:
	set main_projects_key "$user_id-$main_project_id"
 	if {![info exists member_of_main_project_hash($key)]} { continue }

	# Get the hierarchy for the main project as a list-of-lists (lol)
	set hierarchy_lol $main_project_hierarchy_hash($main_project_id)
	set open_p "c"
	if {[info exists collapse_hash($user_id)]} { set open_p $collapse_hash($user_id) }
	if {"c" == $open_p} { set hierarchy_lol [list] }

	# Loop through the project hierarchy
	foreach row $hierarchy_lol {

	    # Extract the pieces of a hierarchy row
	    set project_id [lindex $row 0]
	    set project_name [lindex $row 1]
	    set project_level [lindex $row 2]
	    set project_path [lindex $row 3]
	    set project_tree_sortkey [lindex $row 4]

	    # Iterate through the project_path, looking for:
	    # - the name of the project to display and
	    # - if any of the parents has been closed
	    ns_log Notice "gantt-resources-planning: pid=$project_id, name=$project_name, level=$project_level, path=$project_path, row=$row"
	    set collapse_control_oid 0
	    set closed_p "c"
	    if {[info exists collapse_hash($user_id)]} { set closed_p $collapse_hash($user_id) }
	    for {set i 0} {$i < [llength $project_path]} {incr i} {
		set project_in_path_id [lindex $project_path $i]

		if {$i == [expr [llength $project_path] - 1]} {

		    # We are at the last element of the project "path" - This is the project to display.
		    set pid $project_in_path_id

		} else {

		    # We are at a parent (of any level) of the project
		    # Check if the parent is closed:
		    set collapse_p "c"
		    if {[info exists collapse_hash($project_in_path_id)]} { set collapse_p $collapse_hash($project_in_path_id) }
		    if {"c" == $collapse_p} { set closed_p "c" }

		}
	    }

	    # append the values to the left scale
	    if {"c" == $closed_p} { continue }
	    lappend left_scale [list $user_id $pid]

	}
    }


    # ------------------------------------------------------------------
    # Calculate the main resource assignment hash by looping
    # through the project hierarchy x looping through the date dimension
    # 
    db_foreach percentage_loop $percentage_sql {

	# Loop through the days between start_date and end_data
	for {set i $child_start_date_julian} {$i <= $child_end_date_julian} {incr i} {

	    # Loop through the project hierarchy towards the top
	    set pid $project_id
	    set continue 1
	    while {$continue} {

		# Aggregate per day
		if {$calc_day_p} {
		    set key "$user_id-$pid-$i"
		    set perc 0
		    if {[info exists perc_day_hash($key)]} { set perc $perc_day_hash($key) }
		    set perc [expr $perc + $percentage]
		    set perc_day_hash($key) $perc
		}

		# Aggregate per week
		if {$calc_week_p} {
		    set week_julian [util_memoize [list im_date_julian_to_week_julian $i]]
		    set key "$user_id-$pid-$week_julian"
		    set perc 0
		    if {[info exists perc_week_hash($key)]} { set perc $perc_week_hash($key) }
		    set perc [expr $perc + $percentage]
		    set perc_week_hash($key) $perc
		}

		# Check if there is a super-project and continue there.
		# Otherwise allow for one iteration with an empty $pid
		# to deal with the user's level
		if {"" == $pid} { 
		    set continue 0 
		} else {
		    set pid $parent_hash($pid)
		}
	    }
	}
    }


    # ------------------------------------------------------------
    # Create upper date dimension

    # Top scale is a list of lists like {{2006 01} {2006 02} ...}
    set top_scale {}
    set last_top_dim {}
    for {set i $start_date_julian} {$i <= $end_date_julian} {incr i} {

	array unset date_hash
	array set date_hash [im_date_julian_to_components $i]
	
	set top_dim {}
	foreach top_var $top_vars {
	    lappend top_dim $date_hash($top_var)
	}

	# "distinct" clause: add the values of top_vars to the top scale, 
	# if it is different from the last one...
	# This is necessary for aggregated top scales like weeks and months.
	if {$top_dim != $last_top_dim} {
	    lappend top_scale $top_dim
	    set last_top_dim $top_dim
	}
    }

    # ------------------------------------------------------------
    # Display the Table Header
    
    # Determine how many date rows (year, month, day, ...) we've got
    set first_cell [lindex $top_scale 0]
    set top_scale_rows [llength $first_cell]
    set left_scale_size [llength [lindex $left_vars 0]]

    set header ""
    for {set row 0} {$row < $top_scale_rows} { incr row } {
	
	append header "<tr class=rowtitle>\n"
	set col_l10n [lang::message::lookup "" "intranet-ganttproject.Dim_[lindex $top_vars $row]" [lindex $top_vars $row]]
	if {0 == $row} {
	    set zoom_in "<a href=[export_vars -base $this_url {top_vars {zoom "in"}}]>[im_gif "magnifier_zoom_in"]</a>\n" 
	    set zoom_out "<a href=[export_vars -base $this_url {top_vars {zoom "out"}}]>[im_gif "magifier_zoom_out"]</a>\n" 
	    set col_l10n "<!-- $zoom_in $zoom_out --> $col_l10n\n" 
	}
	append header "<td class=rowtitle colspan=$left_scale_size align=right>$col_l10n</td>\n"
	
	for {set col 0} {$col <= [expr [llength $top_scale]-1]} { incr col } {
	    
	    set scale_entry [lindex $top_scale $col]
	    set scale_item [lindex $scale_entry $row]
	    
	    # Check if the previous item was of the same content
	    set prev_scale_entry [lindex $top_scale [expr $col-1]]
	    set prev_scale_item [lindex $prev_scale_entry $row]

	    # Check for the "sigma" sign. We want to display the sigma
	    # every time (disable the colspan logic)
	    if {$scale_item == $sigma} { 
		append header "\t<td class=rowtitle>$scale_item</td>\n"
		continue
	    }

	    # Prev and current are same => just skip.
	    # The cell was already covered by the previous entry via "colspan"
	    if {$prev_scale_item == $scale_item} { continue }
	    
	    # This is the first entry of a new content.
	    # Look forward to check if we can issue a "colspan" command
	    set colspan 1
	    set next_col [expr $col+1]
	    while {$scale_item == [lindex [lindex $top_scale $next_col] $row]} {
		incr next_col
		incr colspan
	    }
	    append header "\t<td class=rowtitle colspan=$colspan>$scale_item</td>\n"
	}
	append header "</tr>\n"
    }
    append html $header


    # ------------------------------------------------------------
    # Display the table body
    set row_ctr 0
    foreach left_entry $left_scale {

	ns_log Notice "gantt-resources-planning: left_entry=$left_entry"
	set row_html ""

	# ------------------------------------------------------------
	# Start the row and show the left_scale values at the left
	set class $rowclass([expr $row_ctr % 2])
	append row_html "<tr class=$class valign=bottom>\n"

	# Extract user and project. An empty project indicates 
	# an entry for a person only.
	set user_id [lindex $left_entry 0]
	set project_id [lindex $left_entry 1]

	# Determine what we want to show in this line
	set oid $user_id
	set otype "person"
	if {"" != $project_id} { 
	    set oid $project_id 
	    set otype "im_project"
	}
	if {[info exists object_type_hash($oid)]} { set otype $object_type_hash($oid) }

	# Display +/- logic
	set closed_p "c"
	if {[info exists collapse_hash($oid)]} { set closed_p $collapse_hash($oid) }
	if {"o" == $closed_p} {
	    set url [export_vars -base $collapse_url {page_url return_url {open_p "c"} {object_id $oid}}]
	    set collapse_html "<a href=$url>[im_gif minus_9]</a>"
	} else {
	    set url [export_vars -base $collapse_url {page_url return_url {open_p "o"} {object_id $oid}}]
	    set collapse_html "<a href=$url>[im_gif plus_9]</a>"
	}

	set object_has_children_p 0
	if {[info exists has_children_hash($oid)]} { set object_has_children_p $has_children_hash($oid) }
	if {!$object_has_children_p} { set collapse_html "[im_gif cleardot "" 0 9 9]" }

	switch $otype {
	    person {
		set indent_level 0
		set user_name "undef user $oid"
		if {[info exists object_name_hash($oid)]} { set user_name $object_name_hash($oid) }
		set cell_html "$collapse_html [im_gif user] <a href='[export_vars -base $user_base_url {{user_id $oid}}]'>$user_name</a>"
	    }
	    im_project {
		set indent_level 1
		set project_name "undef project $oid"
		if {[info exists object_name_hash($oid)]} { set project_name $object_name_hash($oid) }
		set cell_html "$collapse_html [im_gif cog] <a href='[export_vars -base $project_base_url {{project_id $oid}}]'>$project_name</a>"
	    }
	    im_timesheet_task {
		set indent_level 1
		set project_name "undef project $oid"
		if {[info exists object_name_hash($oid)]} { set project_name $object_name_hash($oid) }
		set cell_html "$collapse_html [im_gif time] <a href='[export_vars -base $project_base_url {{project_id $oid}}]'>$project_name</a>"
	    }
	    default { 
		set cell_html "unknown object '$otype' type for object '$oid'" 
	    }
	}

	# Indent the object name
	if {[info exists indent_hash($oid)]} { set indent_level $indent_hash($oid) }
	set indent_html ""
	for {set i 0} {$i < $indent_level} {incr i} { append indent_html "&nbsp; &nbsp; &nbsp; " }

	append row_html "<td><nobr>$indent_html$cell_html</nobr></td>\n"


	# ------------------------------------------------------------
	# Write the left_scale values to their corresponding local 
	# variables so that we can access them easily when calculating
	# the "key".
	for {set i 0} {$i < [llength $left_vars]} {incr i} {
	    set var_name [lindex $left_vars $i]
	    set var_value [lindex $left_entry $i]
	    set $var_name $var_value
	}
	
	# ------------------------------------------------------------
	# Start writing out the matrix elements
	set last_julian 0
	foreach top_entry $top_scale {

	    # Write the top_scale values to their corresponding local 
	    # variables so that we can access them easily for $key
	    for {set i 0} {$i < [llength $top_vars]} {incr i} {
		set var_name [lindex $top_vars $i]
		set var_value [lindex $top_entry $i]
		set $var_name $var_value
	    }

	    # Calculate the julian date for today from top_vars
	    set julian_date [im_date_components_to_julian $top_vars $top_entry]
	    if {$julian_date == $last_julian} {
		# We're with the second ... seventh entry of a week.
		continue
	    } else {
		set last_julian $julian_date
	    }
	    array unset date_comps
	    array set date_comps [im_date_julian_to_components $julian_date]
	
	    # Get the value for this cell
	    set val ""
	    if {$calc_day_p} {
		set key "$user_id-$project_id-$julian_date"
		if {[info exists perc_day_hash($key)]} { set val $perc_day_hash($key) }
	    }
	    if {$calc_week_p} {
		set week_julian [util_memoize [list im_date_julian_to_week_julian $julian_date]]
		ns_log Notice "intranet-ganttproject-procs: julian_date=$julian_date, week_julian=$week_julian"
		set key "$user_id-$project_id-$week_julian"
		if {[info exists perc_week_hash($key)]} { set val $perc_week_hash($key) }
		if {"" == [string trim $val]} { set val 0 }
		set val [expr round($val / 7.0)]
	    }

	    if {"" == [string trim $val]} { set val 0 }

	    set cell_html [util_memoize [list im_ganttproject_resource_planning_cell $val]]

	    
	    # Lookup the color of the absence for field background color
	    # Weekends
	    set list_of_absences ""
	    if {$calc_day_p && [info exists weekend_hash($julian_date)]} {
		set key $julian_date
		append list_of_absences $weekend_hash($key)
	    }
	
	    # Absences
	    set key "$julian_date-$user_id"
	    if {[info exists absences_hash($key)]} {
		append list_of_absences $absences_hash($key)
	    }
	
	    set col_attrib ""
	    if {"" != $list_of_absences} {
		set color [im_absence_mix_colors $list_of_absences]
		set col_attrib "bgcolor=#$color"
	    }
	    append row_html "<td $col_attrib>$cell_html</td>\n"

	}
	append html $row_html
	append html "</tr>\n"
	incr row_ctr
    }

    # ------------------------------------------------------------
    # Close the table

    set html "<table cellspacing=0 cellpadding=0>\n$html\n</table>\n"

    if {0 == $row_ctr} {
	set no_rows_msg [lang::message::lookup "" intranet-ganttproject.No_rows_selected "
		No rows found.<br>
		Maybe there are no assignments of users to projects in the selected period?
	"]
	append html "<br><b>$no_rows_msg</b>\n"
    }


    return $html
}

