"""Valida la sintaxis de un .sql con el parser REAL de Postgres (pglast):
1) el archivo entero, 2) el cuerpo de cada DO / CREATE FUNCTION en plpgsql,
3) el SQL que arma cada format($f$...$f$) con valores de relleno.
No ejecuta nada ni necesita una base. Solo SINTAXIS: no comprueba que existan las
tablas, columnas ni funciones que nombra (eso solo lo dice pegarlo en la base).
Lo usa verificar.py (regla `sql_sintaxis`); requiere `pip install pglast`."""
import re, sys
import pglast
from pglast import parse_sql, parse_plpgsql

def _pl(cuerpo):
    # Solo se mira la SINTAXIS: el tipo de retorno se elige según el cuerpo para
    # que `RETURN QUERY` o `RETURN valor` no den falsos errores.
    if re.search(r'RETURN\s+QUERY', cuerpo, re.I): t = 'SETOF record'
    elif re.search(r'RETURN\s+(?!QUERY|;|NEXT)\S', cuerpo, re.I): t = 'text'
    else: t = 'void'
    return parse_plpgsql('CREATE FUNCTION _t() RETURNS %s LANGUAGE plpgsql AS $x$ %s $x$' % (t, cuerpo))

def validar(ruta):
    s = open(ruta, encoding='utf-8').read()
    malos = []
    try:
        arbol = parse_sql(s)
    except Exception as e:
        return ['SQL: %s' % e]
    for st in arbol:
        nodo = st.stmt
        tag = type(nodo).__name__
        if tag == 'DoStmt':
            for a in nodo.args:
                if a.defname == 'as':
                    cuerpo = a.arg.sval
                    try:
                        _pl(cuerpo)
                    except Exception as e:
                        malos.append('DO plpgsql: %s' % e)
                    # lo que se arma con format($f$ ... $f$, ...)
                    for m in re.finditer(r"format\(\s*\$f\$(.*?)\$f\$", cuerpo, re.S):
                        molde = re.sub(r'%[sIL]', 'x', m.group(1))
                        molde = molde.replace('RETURNS x', 'RETURNS TABLE (a text)')
                        try:
                            parse_sql(molde)
                            for st2 in parse_sql(molde):
                                if type(st2.stmt).__name__ == 'CreateFunctionStmt':
                                    for o in st2.stmt.options:
                                        if o.defname == 'as':
                                            _pl(o.arg[0].sval)
                        except Exception as e:
                            malos.append('format(): %s' % e)
        elif tag == 'CreateFunctionStmt':
            leng = [o.arg.sval for o in nodo.options if o.defname == 'language']
            cuerpo = [o.arg[0].sval for o in nodo.options if o.defname == 'as']
            if leng and leng[0] == 'plpgsql' and cuerpo:
                try:
                    _pl(cuerpo[0])
                except Exception as e:
                    malos.append('CREATE FUNCTION plpgsql: %s' % e)
    return malos

if __name__ == '__main__':
    todo_bien = True
    for ruta in sys.argv[1:]:
        m = validar(ruta)
        print(('OK    ' if not m else 'FALLA ') + ruta)
        for x in m:
            print('      -', x)
            todo_bien = False
    sys.exit(0 if todo_bien else 1)
