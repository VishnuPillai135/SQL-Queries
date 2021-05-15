
--Vishnu Pillai

-- Q1: students who've studied many courses

create view Q1(unswid,name)
as
select   
	People.unswid, 
    People.name 
from 
	People 
	join 
		Students on (People.id = Students.id) 
	join 
		Course_enrolments on (Students.id = Course_enrolments.student) 
group by 
	Students.id, 
	People.name, 
	People.unswid 
having 
	count(*) > 65
order by 
	people.unswid
;




-- Q2: numbers of students, staff and both

create or replace view Q2(nstudents,nstaff,nboth)
as
select
	count(*) FILTER (WHERE Staff.id IS NULL),
	count(*) FILTER (WHERE Students.id IS NULL), 
	count(*) FILTER (WHERE Staff.id IS NOT NULL AND Students.id IS NOT NULL)
from 
	Students
   	full outer join Staff on (Students.id = Staff.id)
;



-- Q3: prolific Course Convenor(s)

-- create list of names and the amount of courses
create or replace view Q3part1(name, ncourses)
as
select	
	People.name, 
	count(*) 
from 
	People
   	join Course_staff on (Course_staff.staff = People.id)
   	join Staff on (People.id = Staff.id)
   	join Staff_roles on (Staff_roles.id = Course_staff.role)
where 
	Staff_roles.name = 'Course Convenor'
group by 
	People.name, 
	Course_staff.staff
order by 
	count(*) DESC
;


-- select the max result from the above list
create or replace view Q3(name, ncourses)
as
select 
	name, 
	ncourses
from 
	Q3part1
where 
	ncourses = (select max(ncourses) from Q3part1);



-- Q4: Comp Sci students in 05s2 and 17s1

create or replace view Q4a(id,name)
as
select 
	People.unswid, 
	People.name 
from 
	People
	join Students on (People.id = Students.id)
	join Program_enrolments on (Program_enrolments.student = Students.id)
	join Terms on (Program_enrolments.term = Terms.id)
	join Programs on (Program_enrolments.program = Programs.id)
where 
	Programs.code = '3978' AND 
	Terms.year = 2005 AND 
	Terms.session = 'S2'
order by 
	People.unswid ASC
;



create or replace view Q4b(id,name)
as
select 
	People.unswid, 
	People.name 
from 
	People
	join Students on (People.id = Students.id)
	join Program_enrolments on (Program_enrolments.student = Students.id)
	join Terms on (Program_enrolments.term = Terms.id)
	join Programs on (Program_enrolments.program = Programs.id)
where 
	Programs.code = '3778' AND 
	Terms.year = 2017 AND 
	Terms.session = 'S1'
order by 
	People.unswid ASC
;



-- Q5: most "committee"d faculty

--apply facultyOf() to all OrgUnits and return a list
create or replace view Q5part1(id, count)
as
select 
	facultyOf(OrgUnits.id), 
	count(*) 
from 
	OrgUnits 
where 
	OrgUnits.utype = 9 and 
	facultyOf(OrgUnits.id) is not null 
group by 
	facultyOf(OrgUnits.id)
order by 
	count(*) 
;


-- choose max from above list
create or replace view Q5part2(id, count)
as
select 
	id, 
	count
from 
	Q5part1
where 
	count = (select max(count) from Q5part1);


-- link ids from above to names
create or replace view Q5(name)
as
select 
	OrgUnits.name 
from 
	OrgUnits
	join Q5part2 on (OrgUnits.id = Q5part2.id)
;



-- Q6: nameOf function

create or replace function
   Q6(id integer) returns text
as $$
select 
	People.name 
from 
	People
where 
	People.id = $1 or 
	People.unswid = $1
$$ language sql;



-- Q7: offerings of a subject

--list of subject codes, terms, and names where there's a course convenor
create or replace view Q7part1(subject1, term1, convenor1) 
as
select 
	Subjects.code, 
	Courses.term, 
	People.name 
from 
	Staff_roles
	join Course_staff on (Staff_roles.id = Course_staff.role)
	join Courses on (Course_staff.course = Courses.id)
	join Subjects on (Subjects.id = Courses.subject)
	join People on (People.id = Course_staff.staff)
where 
	Staff_roles.name = 'Course Convenor';


-- specify what Subjects.code is in the above view
create or replace function
   Q7(subject text)
     returns table (subject text, term text, convenor text)
as $$
select 
	cast(subject1 as text), 
	termname(term1), 
	convenor1 :: Text 
from 
	Q7part1 
where 
	Q7part1.subject1 = $1
$$ language sql;



-- Q8: transcript

create or replace function
   Q8(zid integer) returns setof TranscriptRecord
as $$
declare 
	transcript TranscriptRecord;
	zID integer;
	wamValue integer := 0;
	weightedSumOfMarks float := 0;
	totalUOCattempted integer:= 0;
	UOCpassed integer := 0;
	randomVariable integer;
begin 
perform 
	Students.id 
from 
	Students 
	join People on (People.id = Students.id)
where 
	People.unswid = $1;
if (not found) then
	raise EXCEPTION 'Invalid student %', $1;
end if;
for transcript in
--create list of transcripts without any duplicates 
select 
	Subjects.code, 
	termname(Courses.term), 
	Programs.code, 
	substr(Subjects.name, 1, 20) as shortName,
	Course_enrolments.mark, 
	Course_enrolments.grade, 
	Subjects.uoc 
from Course_enrolments
	join Courses on (Courses.id = Course_enrolments.course)
	join Subjects on (Subjects.id = Courses.subject)
	join Terms on (Terms.id = Courses.term)
	join Students on (Students.id = Course_enrolments.student)
	join People on (People.id = Students.id)
	join Program_enrolments on (Program_enrolments.student = Students.id)
	join Programs on (Programs.id = Program_enrolments.program)
where 
	Program_enrolments.term = Courses.term and 
	People.unswid = $1
group by 
	Subjects.code, 
	Courses.term, 
	Programs.code, 
	shortName,
	Course_enrolments.mark, 
	Course_enrolments.grade, 
	Subjects.uoc,
    Terms.starting
order by 
	Terms.starting, 
	Subjects.code
	
-- use above list to calculate wam
loop 
	if (transcript.mark is not null) then
		if (transcript.grade in ('PT', 'PC', 'PS', 'CR', 'DN', 'HD', 'A', 'B', 'C')) then
			UOCpassed := UOCpassed + transcript.uoc;
            totalUOCattempted := totalUOCattempted + transcript.uoc;
            weightedSumOfMarks := weightedSumOfMarks + (transcript.mark * transcript.uoc);
		else  
            totalUOCattempted := totalUOCattempted + transcript.uoc;
            weightedSumOfMarks := weightedSumOfMarks + (transcript.mark * transcript.uoc);
            transcript.uoc := null;
		end if;
      	elsif (transcript.grade in ('SY', 'XE', 'T', 'PE')) then
			UOCpassed := UOCpassed + transcript.uoc;
		end if;
	return next transcript;
end loop;

if (totalUOCattempted = 0) then
	transcript := (null, null, null, 'No WAM available', null, null, null);
else 
	wamValue := round(weightedSumOfMarks / totalUOCattempted);
	transcript := (null, null, null, 'Overall WAM/UOC', wamValue, null, UOCpassed);
end if;
return next transcript;
end;
$$ language plpgsql;



-- Q9: members of academic object group

-- create or replace function
--    Q9(gid integer) returns setof AcObjRecord
-- as $$
-- ...
-- $$ language plpgsql;



-- Q10: follow-on courses

-- find list, specifically for pre-reqs
create or replace view Q10part1
as
select 
	Subjects.code, 
	Acad_object_groups.definition 
from 
	Subject_prereqs
	join Subjects on (Subjects.id = Subject_prereqs.subject)
	join Rules on (Rules.id = Subject_prereqs.rule)
	join Acad_object_groups on (Acad_object_groups.id = Rules.ao_group)
where 
	Rules.type = 'RQ'
;



-- have acad_object_groups.id equal input
create or replace function
   Q10(code text) returns setof text
as $$
declare
   preReqSet text;
begin 
for preReqSet in 
select 
	Q10part1.code 
from 
	Q10part1
where 
	Q10part1.definition ~* $1
loop  
	return next preReqSet;
end loop;
end;
$$ language plpgsql;
