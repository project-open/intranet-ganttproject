<master>
<property name="doc(title)">@page_title;literal@</property>
<property name="context">@context_bar;literal@</property>
<property name="main_navbar_label">projects</property>
<property name="sub_navbar">@sub_navbar;literal@</property>


<h1><%= [lang::message::lookup "" intranet-ganttproject.TaskJuggler_Schedule_Successfully_Imported "
TaskJuggler Schedule Successfully Imported
"] %></h1>

<p>
<%= [lang::message::lookup "" intranet-ganttproject.Schedule_Imported_msg "
Your TaskJuggler schedule has been successfully imported into \]project-open\[.<br>
The following Gantt diagram shows the results.
"] %>
</p>



@content;noquote@

