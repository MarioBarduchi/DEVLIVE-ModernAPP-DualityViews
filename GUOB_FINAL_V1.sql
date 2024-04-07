--===================================================================================================================================================
-- Docker 
--===================================================================================================================================================
-- docker run -d -it --name Orcl23c -p 1527:1521 -p 5507:5500 -p 8087:8080 -p 8447:8443 -e ORACLE_PWD=E container-registry.oracle.com/database/free:latest
-- Portas:
--	Ori:-p 8521:1521 -p 8500:5500 -p 8023:8080 -p 9043:8443

--docker ps --format "table {{.ID}}\t{{.Status}}\t{{.Names}}\t{{.Ports}}"
--docker ps -f status=running --format "table {{.ID}}\t{{.Status}}\t{{.Names}}\t{{.Ports}}"

--docker start Orcl23c
--docker stop Orcl23c

--===================================================================================================================================================
-- Create user 
--===================================================================================================================================================
sqlplus / as sysdba
ALTER SESSION SET CONTAINER = FREEPDB1;
create user guob2 identified by Password123###;
grant create session to guob2;
grant RESOURCE to guob2;
grant unlimited tablespace to guob2;
conn guob2/Password123###@localhost:1521/freepdb1

--===================================================================================================================================================
-- Criando as tabelas iniciais 
--===================================================================================================================================================
drop table if exists emp purge;
drop table if exists dept purge;

create table dept (
  deptno number(2) constraint pk_dept primary key,
  dname varchar2(20),
  loc varchar2(20)
) ;

create table emp (
  empno number(4) constraint pk_emp primary key,
  ename varchar2(20),
  job varchar2(20),
  mgr number(4),
  hiredate date,
  sal number(7,2),
  comm number(7,2),
  deptno number(2) constraint fk_deptno references dept
);

create index emp_dept_fk_i on emp(deptno);

insert into dept values (10,'IT','Sao Paulo');
insert into dept values (20,'Saude','Sao Paulo');
insert into dept values (30,'Diretoria','Sao Paulo');
insert into dept values (40,'Operacoes','Brasilia');

insert into emp values (1,'Mario','DBA',3,to_date('10-11-2019','dd-mm-yyyy'),28000,null,10);
insert into emp values (2,'Vanessa','Enfermeira',3,to_date('15-10-2021','dd-mm-yyyy'),9000,null,20);
insert into emp values (3,'Luna','CEO',null,to_date('11-12-2017','dd-mm-yyyy'),80000,5000,30);
insert into emp values (4,'Draco','Analista',1,to_date('14-12-2020','dd-mm-yyyy'),5000,null,10);
insert into emp values (5,'Winsley','DBRE',1,to_date('12-12-2019','dd-mm-yyyy'),8000,null,10);

commit;

--===================================================================================================================================================
-- Verificando dados das tabelas 
--===================================================================================================================================================
set pages 120 lines 1000;
SELECT
	e.empno,
	e.ename,
	e.job,
	e.sal,
	e.mgr,
	ee.ename as Manager,
	d.deptno,
	d.dname,
	d.loc
FROM
	emp e
JOIN dept d ON d.deptno = e.deptno
LEFT JOIN emp ee ON ee.empno = e.mgr
ORDER BY 1,4;

--===================================================================================================================================================
-- Criando a primeira JSON-Relational Duality View
-- DEPARTMENT_DV = Lista informações sobre o departamento, incluindo uma matriz de funcionários dentro do departamento. 
--			           Para cada tabela, definimos as operações que são possíveis. 
--                 Aqui definimos com "WITH INSERT UPDATE DELETE".
--===================================================================================================================================================
CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW department_dv AS
	SELECT JSON {
					'departmentNumber' : d.deptno,
					'departmentName'   : d.dname,
					'location'         : d.loc,
					'employees'		     :
						   [ 
							SELECT JSON {
											'employeeNumber' : e.empno,
											'employeeName'   : e.ename,
											'job'            : e.job,
											'salary'         : e.sal
										}
							FROM emp e WITH INSERT noUPDATE DELETE
							WHERE 
								d.deptno = e.deptno 
						   ]
			   }
FROM dept d WITH INSERT UPDATE DELETE;

desc department_dv

set long 1000000 pagesize 1000 linesize 100

select * from department_dv;

-- Usando o JSON_SERIALIZE para deixar a apresentação mais friendly
select json_serialize(d.data) from department_dv d;
select json_serialize(d.data pretty) from department_dv d;

--===================================================================================================================================================
-- Nós podemos usar também a notação de GraphQL para criar a view. 
-- Neste exemplo, referenciamos as tabelas e as colunas e o Oracle database estabelece a relação entre as 
-- tabelas utilizando as PKs e FKs.
--===================================================================================================================================================
CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW department2_dv AS
dept @INSERT @UPDATE @DELETE
{
  departmentNumber: deptno
  departmentName  : dname
  location        : loc
  employees       : emp @INSERT @UPDATE @NODELETE
  {
	  employeeNumber  : empno
    employeeName    : ename
    job             : job
    salary          : sal @NOUPDATE
  }
};

set long 1000000 pagesize 1000 linesize 100
select json_serialize(d.data pretty) from department2_dv d;


--===================================================================================================================================================
-- A palavra-chave UNNEST especifica quando as propriedades em um objeto aninhado não devm ser aninhada no objeto pai. 
-- Nesses exemplo, foi criada a view de EMPLOYEE_DV, que contém informações dos funcionários, juntamente com as 
-- informações do departamento associado para cada funcionário em um documento simples. 
--===================================================================================================================================================
CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW employee_dv AS
emp @INSERT @UPDATE @DELETE
{
  employeeNumber : empno
  employeeName : ename
  job : job
  salary : sal
  dept @unnest @update
  {
    departmentNumber : deptno
    departmentName : dname
    location : loc
  }
};

set long 1000000 pagesize 1000 linesize 100
select json_serialize(d.data pretty) from employee_dv d;

--===================================================================================================================================================
-- Filtrando somente o departamento 10
-- Cara linha contém um Document JSON definindo o departamento e quais 
-- funcionários fazem parte daquele deparetamento.
--===================================================================================================================================================
column departmentname format A20
column location format A20

select d.data.departmentName,
       d.data.location
from   department_dv d
where  d.data.departmentNumber = 10;

select json_serialize(d.data pretty)
from   department_dv d
where  d.data.departmentNumber = 10;

select json_serialize(d.data pretty)
from   department2_dv d
where  d.data.departmentNumber = 10;


--===================================================================================================================================================
-- EMPLOYEE_DV = Informações sobre os funcionários, juntamente com as informações de departamento associadas 
-- a cada funcionário em um documento plano. 
-- Podemos utilizar DML convencional nas tabelas de base para modificar os dados, mas agora também podemos 
-- trabalhar diretamente em documents JSON.
-- Com o UNNEST conseguimos "produzir" documents planos ao anular o resultado de uma subconsulta. Basicamente 
-- não temos um sub-Array de dados.
-- Com NOCHECK, uma coluna pode ser excluída do cálculo do ETAG.
-- ===================================================================================================================================================
CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW employee_dv AS
	SELECT JSON {
					'employeeNumber' : e.empno,
					'employeeName'   : e.ename,
					'job'            : e.job,
					'salary'         : e.sal,
				unnest (
						SELECT JSON {
										'departmentNumber' : d.deptno,
										'departmentName'   : d.dname,
										'location'         : d.loc WITH NOCHECK     
									}
						FROM dept d WITH UPDATE
						WHERE d.deptno = e.deptno
						)
				}
FROM emp e WITH INSERT UPDATE DELETE;

set long 1000000 pagesize 1000 linesize 100
select json_serialize(d.data pretty) from employee_dv d;

-- GraphQL
CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW employee2_dv AS
emp @INSERT @UPDATE @DELETE
{
  employeeNumber : empno
  employeeName   : ename
  job            : job
  salary         : sal
  dept @UNNEST @UPDATE
  {
    departmentNumber: deptno
    departmentName  : dname
    location        : loc @NOCHECK
  }
};


--===================================================================================================================================================
-- Podemos inserir dados diretamewnte nas tabelas usando notação JSON 
--===================================================================================================================================================
insert into department_dv d (data) values 
('
	{
		"departmentNumber" : 50,
		"departmentName" : "Exportacao",
		"location" : "Amazonas",
		"employees" : [
						{
							"employeeNumber" : 4,
							"employeeName"   : "Doo",
							"job"            : "Piloto",
							"salary"         : 5000
						}
					  ]
	}
');

select json_serialize(d.data pretty)
from   department_dv d
where  d.data.departmentNumber = 50;

select * from dept where deptno = 50;
select * from emp where deptno = 50;
rollback;

===================================================================================================================================================
-- ETAG 
-- Precisamos certificar que a versão/estado do document não foi alterado após sua chamada. 
-- E em “operações sem estado” como PUT, GET, os algoritmos de lock não mantém bloqueios efetivos. 
-- Uma maneira de implementar isso é usar o “Optimistic Concurrency Control” que é um Lock-free algorithm. 
-- Para as DV é utilizado o “Lock-free concurrency control algorithm". Esse algoritmo permite que atualizações 
-- consistentes sejam realizadas em operações sem estado.
-- Por default, todo document em uma DV registra o seu estado em um campo Entity Tag (ETAG). O valor desse campo 
-- é um HASH calculado pelo conteúdo do document, e mais algumas informações, e é renovado automaticamente sempre 
-- que esse document é recuperado.
-- Quando uma atualização é realizada, o JSON devolvido contém um ETAG calculado e uma comparação com o ETAG atual 
-- do document é feita. Se os ETAGs forem diferentes, o document foi modificado e a atualização será rejeitada. 
-- Sendo assim, temos a garantia de que não ocorreram alterações no document, assegurando a atomicidade e a 
-- consistência a nível do document. 
-- Todos os campos de um document contribuem para o cálculo do ETAG. Para excluir um determinado campo do cálculo, 
-- usamos o NOCHECK. Se todas as colunas forem NOCHECK, nenhum campo será validado. 
-- Isso pode melhorar muito o desempenho para documentos maiores. Você pode querer excluir as verificações do ETAG em:
--    Um APP que tem seu próprio controle de consistência e não precisa do ETAG;
--    Um APP Single thread, que não é possível fazer modificações simultâneas.
===================================================================================================================================================
insert into department_dv d (data)
values ('
{
  "departmentNumber" : 50,
  "departmentName" : "DBA",
  "location" : "BIRMINGHAM",
  "employees" : [
    {
      "employeeNumber" : 9999,
      "employeeName" : "HALL",
      "job" : "CLERK",
      "salary" : 500
    }
  ]
}');

set long 1000000 pagesize 1000 linesize 100
select json_serialize(d.data pretty)
from   department_dv d
where  d.data.departmentNumber = 50;


insert into emp values (9996,'Stark','IRONMAN',null,null,30000,null,50);
commit;


-- Before: 77052B06E84B60749E410D5C2BA797DF
update department_dv d
set d.data = ('
{
  "_metadata" : {"etag" : "77052B06E84B60749E410D5C2BA797DF"},
  "departmentNumber" : 50,
  "departmentName" : "DBA",
  "location" : "BIRMINGHAM",
  "employees" : [
    {
      "employeeNumber" : 9999,
      "employeeName" : "ZEZITO",
      "job" : "SALESMAN",
      "salary" : 1000
    }
  ]
}')
where d.data.departmentNumber = 50;


set long 1000000 pagesize 1000 linesize 100
select json_serialize(d.data pretty)
from   department_dv d
where  d.data.departmentNumber = 50;

-- After: 1CA58D18CD68DFCA3D1C5A3EFC167957
update department_dv d
set d.data = ('
{
  "_metadata" : {"etag" : "1CA58D18CD68DFCA3D1C5A3EFC167957"},
  "departmentNumber" : 50,
  "departmentName" : "DBA AVG",
  "location" : "LONDON",
  "employees" : [
    {
      "employeeNumber" : 7777,
      "employeeName" : "MASTER",
      "job" : "IRONMAN",
      "salary" : 50000
    }
  ]
}')
where d.data.departmentNumber = 50;

commit;

select json_serialize(d.data pretty)
from   department_dv d
where  d.data.departmentNumber = 50;

===================================================================================================================================================
-- ORDS - Oracle REST Data Services
===================================================================================================================================================
BEGIN
    ORDS.ENABLE_OBJECT(
        P_ENABLED => TRUE,
        P_SCHEMA => 'guob2',
        P_OBJECT => 'DEPARTMENT_DV',
        P_OBJECT_TYPE => 'VIEW',
        P_OBJECT_ALIAS => 'department_dv',
        P_AUTO_REST_AUTH => FALSE
    );
    COMMIT;
END;
/

BEGIN
    ORDS.ENABLE_OBJECT(
        P_ENABLED => TRUE,
        P_SCHEMA => 'guob2',
        P_OBJECT => 'EMPLOYEE_DV',
        P_OBJECT_TYPE => 'VIEW',
        P_OBJECT_ALIAS => 'employee_dv',
        P_AUTO_REST_AUTH => FALSE
    );
    COMMIT;
END;
/

BEGIN
    ORDS.ENABLE_SCHEMA(p_enabled => TRUE,
                       p_schema => 'guob2',
                       p_url_mapping_type => 'BASE_PATH',
                       p_url_mapping_pattern => 'guob2',
                       p_auto_rest_auth => FALSE);
    COMMIT;
END;
/

## Exemplo
http://localhost:8087/ords/guob2/employee_dv/
http://localhost:8087/ords/guob2/department_dv/
http://localhost:8087/ords/guob2/department_dv/20


## Visual Studio - Thunder Client
New Request
Method: GET 
http://localhost:8087/ords/guob2/department_dv/

## UPDATE
Method: GET
http://localhost:8087/ords/guob2/department_dv/20


Method: PUT
http://localhost:8087/ords/guob2/department_dv/20

-- JSON Content (Body)
{	
	"_metadata": 
	{
        "etag": "B0BE8FF7CA29CA3931FE04F563727B1C",
        "asof": "0000000000552183"
    },
      "departmentNumber": 20,
      "departmentName": "Saude OCU",
      "location": "Sao Paulo",
      "employees": [
        {
          "employeeNumber": 2,
          "employeeName": "Vanessa",
          "job": "Enfermeira",
          "salary": 9000
        }
      ]
}

set long 1000000 pagesize 1000 linesize 100
select json_serialize(d.data pretty)
from   department_dv d
where  d.data.departmentNumber = 20;

select * from dept where deptno = 20;



--====================
URL='jdbc:oracle:thin:mvn1/Password123##@//localhost:1521/freepdb1'
./run.sh $URL movie.DropTable       -- Drops the table used by the examples.
./run.sh $URL movie.CreateTable     -- Creates the movie table movie used by all the examples.
./run.sh $URL movie.Insert          -- Inserts three JSON values into the movie table.
./run.sh $URL movie.GetAll          -- Gets all the JSON values from the movie table.
./run.sh $URL movie.Filter          -- Selects movies from the movie table where the salary attribute is greater than 30,000.
./run.sh $URL movie.Filter2         -- Selects movies from the movie table that have the created attribute.
./run.sh $URL movie.Update          -- Updates an movie record using whole document replacement.
./run.sh $URL movie.UpdateMerge     -- Performs a partial update using JSON_MERGEPATCH().
./run.sh $URL movie.UpdateTransform -- Performs a partial update using JSON_TRANSFORM().
./run.sh $URL movie.JSONP           -- Inserts and retrieves a value using JSON-P (javax.json) interfaces.
./run.sh $URL movie.JSONB           -- Stores and retrieves a plain/custom Java object as JSON using JSON-B (javax.json.bind).
./run.sh $URL movie.Jackson         -- Encodes JSON from an external source, in this case a Jackson parser, as Oracle binary JSON and inserts it into the table.
./run.sh $URL movie.BinaryJson      -- Encodes JSON text as Oracle binary JSON, stores it in a file, and then reads it back again.
./run.sh $URL movie.RunAll          -- Runs all the examples at once.

--ou 
mvn -q exec:java -Dexec.mainClass="movie.DropTable" -Dexec.args='jdbc:oracle:thin:mvn1/Password123##@//localhost:1521/freepdb1'
-- Droped table movie

mvn -q exec:java -Dexec.mainClass="movie.CreateTable" -Dexec.args='jdbc:oracle:thin:mvn1/Password123##@//localhost:1521/freepdb1'
-- Created table movie

-- Para testes JDBC
sqlplus / as sysdba;
ALTER SESSION SET CONTAINER = FREEPDB1;
grant select on mvn1.movie to guob2;

set long 1000000 pagesize 1000 linesize 100
select json_serialize(d.data pretty)
from   MVN1.movie d;
