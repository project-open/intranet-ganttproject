-- /packages/intranet-ganttproject/sql/postgresql/intranet-ganttproject-create.sql
--
-- Copyright (c) 2003-2006 Project/Open
--
-- All rights reserved. Please check
-- http://www.project-open.com/license/ for details.
--
-- @author frank.bergmann@project-open.com


---------------------------------------------------------
-- Setup a GanttProject component for 
-- /intranet/projects/view page
--


----------------------------------------------------------------
-- percentage column for im_biz_object_members


create or replace function inline_0 ()
returns integer as '
declare
        v_count                 integer;
begin
        select count(*) into v_count from user_tab_columns
        where lower(table_name) = ''im_biz_object_members'' and lower(column_name) = ''percentage'';
        IF 0 != v_count THEN return 0; END IF;

        ALTER TABLE im_biz_object_members ADD column percentage numeric(8,2);
        ALTER TABLE im_biz_object_members ALTER column percentage set default 100;

        return 1;
end;' language 'plpgsql';
select inline_0 ();
drop function inline_0 ();



----------------------------------------------------------------
-- Add new tab to project's menu

create or replace function inline_0 ()
returns integer as'
declare
        -- Menu IDs
        v_menu                  integer;
        v_project_menu          integer;

        -- Groups
        v_accounting            integer;
        v_senman                integer;
        v_sales                 integer;
        v_proman                integer;

begin
    select group_id into v_proman from groups where group_name = ''Project Managers'';
    select group_id into v_senman from groups where group_name = ''Senior Managers'';
    select group_id into v_sales from groups where group_name = ''Sales'';
    select group_id into v_accounting from groups where group_name = ''Accounting'';

    select menu_id into v_project_menu
    from im_menus where label=''project'';

    v_menu := im_menu__new (
        null,                   -- p_menu_id
        ''acs_object'',         -- object_type
        now(),                  -- creation_date
        null,                   -- creation_user
        null,                   -- creation_ip
        null,                   -- context_id
        ''intranet-ganttproject'', -- package_name
        ''project_gantt'',	-- label
        ''Gantt'',               -- name
        ''/intranet-ganttproject/gantt-view-cube?view=default'',  -- url
        120,                    -- sort_order
        v_project_menu,         -- parent_menu_id
        null                    -- p_visible_tcl
    );

    PERFORM acs_permission__grant_permission(v_menu, v_proman, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_senman, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_sales, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_accounting, ''read'');

    return 0;
end;' language 'plpgsql';
select inline_0 ();
drop function inline_0 ();







----------------------------------------------------------------
-- Show the ganttproject component in project page
--
SELECT im_component_plugin__new (
        null,                           -- plugin_id
        'acs_object',                   -- object_type
        now(),                          -- creation_date
        null,                           -- creation_user
        null,                           -- creation_ip
        null,                           -- context_id
        'Project GanttProject Component',      -- plugin_name
        'intranet-ganttproject',               -- package_name
        'right',                        -- location
        '/intranet/projects/view',      -- page_url
        null,                           -- view_name
        10,                            -- sort_order
	'im_ganttproject_component -project_id $project_id -current_page_url $current_url -return_url $return_url -export_var_list [list project_id]',
	'lang::message::lookup "" intranet-ganttproject.Scheduling "Scheduling"'
);



----------------------------------------------------------------
-- Summary components in ProjectViewPage
----------------------------------------------------------------

-- Resource Component with LoD 2 at the right-hand side
SELECT im_component_plugin__new (
        null,                           -- plugin_id
        'acs_object',                   -- object_type
        now(),                          -- creation_date
        null,                           -- creation_user
        null,                           -- creation_ip
        null,                           -- context_id
        'Project Gantt Resource Summary',      -- plugin_name
        'intranet-ganttproject',        -- package_name
        'right',                        -- location
        '/intranet/projects/view',      -- page_url
        null,                           -- view_name
        -13,                            -- sort_order
	'im_ganttproject_resource_component -project_id $project_id -return_url $return_url -export_var_list [list project_id]',
	'lang::message::lookup "" intranet-ganttproject.Project_Gantt_Resource_Assignations "Project Gantt Resource Assignations"'
);



-- Gantt Component with LoD 2 at the right-hand side
SELECT im_component_plugin__new (
        null,                           -- plugin_id
        'acs_object',                   -- object_type
        now(),                          -- creation_date
        null,                           -- creation_user
        null,                           -- creation_ip
        null,                           -- context_id
        'Project Gantt Scheduling Summary', -- plugin_name
        'intranet-ganttproject',	-- package_name
        'right',			-- location
        '/intranet/projects/view',	-- page_url
        null,                           -- view_name
        12,                             -- sort_order
	'im_ganttproject_gantt_component -project_id $project_id -return_url $return_url -export_var_list [list project_id]',
	'lang::message::lookup "" intranet-ganttproject.Project_Gantt_View "Project Gantt View"'
);




----------------------------------------------------------------
-- Detailed components in Gantt tab
----------------------------------------------------------------

-- Gantt Component with LoD 3 in extra tab
SELECT im_component_plugin__new (
        null,                           -- plugin_id
        'acs_object',                   -- object_type
        now(),                          -- creation_date
        null,                           -- creation_user
        null,                           -- creation_ip
        null,                           -- context_id
        'Project Gantt View Details',		-- plugin_name
        'intranet-ganttproject',	-- package_name
        'gantt',			-- location
        '/intranet/projects/view',	-- page_url
        null,                           -- view_name
        100,                             -- sort_order
	'im_ganttproject_gantt_component -project_id $project_id -level_of_detail 3 -return_url $return_url -export_var_list [list project_id]',
	'lang::message::lookup "" intranet-ganttproject.Project_Gantt_View "Project Gantt View"'
);


-- Resource Component with LoD 3 in extra tab
SELECT im_component_plugin__new (
        null,                           -- plugin_id
        'acs_object',                   -- object_type
        now(),                          -- creation_date
        null,                           -- creation_user
        null,                           -- creation_ip
        null,                           -- context_id
        'Project Gantt Resource Details',      -- plugin_name
        'intranet-ganttproject',        -- package_name
        'gantt',                        -- location
        '/intranet/projects/view',      -- page_url
        null,                           -- view_name
        200,                            -- sort_order
	'im_ganttproject_resource_component -project_id $project_id -level_of_detail 3 -return_url $return_url -export_var_list [list project_id]',
	'lang::message::lookup "" intranet-ganttproject.Project_Gantt_Resource_Assignations "Project Gantt Resource Assignations"'
);


