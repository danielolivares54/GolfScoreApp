from pathlib import Path
import json
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.lib.utils import simpleSplit

OUT=Path(__file__).parent
cases=[
('Golpes completos','H6, par 5. Yo = DAN. Sin datos previos.','Hoyo seis: Daniel cinco, Anselmo seis, Roberto siete, Ricardo cinco y Fernando cuatro.','DAN=5; ANS=6; ROB=7; RIC=5; FER=4.'),
('Yo y los demás','H6, par 5. Yo = DAN.','Tiré cinco y los demás bogey.','DAN=5; ANS=6; ROB=6; RIC=6; FER=6. Usar H6 contextual.'),
('Todos','H8, par 4. Yo = DAN.','Todos hicimos par en el ocho.','H8: DAN=ANS=ROB=RIC=FER=4.'),
('Frase corrida','H6, par 5. Yo = DAN.','Yo par, Anselmo birdie, Roberto doble bogey y los demás bogey.','H6: DAN=5; ANS=4; ROB=7; RIC=6; FER=6.'),
('Alias','H8, par 4.','Dani cuatro, Richi cinco, Bob seis y Anse cuatro.','H8: DAN=4; RIC=5; ROB=6; ANS=4. FER sigue pendiente.'),
('Cambio de yo','H6, par 5. Yo = RIC.','Yo cinco y Daniel seis.','RIC=5; DAN=6. No confundir hablante con jugador yo configurado.'),
('Números juntos','H12, par 4.','Hoyo doce, Daniel seis golpes y dos putts.','H12: DAN golpes=6, putts=2. No confundir doce con dos.'),
('Dieciséis y seis','H16, par 3.','En el dieciséis Ricardo hizo seis, con tres putts.','H16: RIC golpes=6, putts=3. Oyes continúa pendiente.'),
('Dos y doce','H2, par 4. Caso de estrés.','Hoyo dos, Roberto doce golpes y dos putts.','H2: ROB golpes=12, putts=2. Número alto: revisar, nunca reducir a 2.'),
('Birdie y eagle','H6, par 5.','Daniel birdie, Ricardo eagle y Fernando par.','DAN=4; RIC=3; FER=5. Eventos calculados desde bruto; no duplicar unidades.'),
('Corrección hablada','H6. DAN aún sin guardar.','Daniel seis... no, cinco.','Borrador DAN=5. La corrección reemplaza seis; requiere confirmar.'),
('Reentrada','H6. DAN=6 ya guardado.','Corrige a Daniel: fueron cinco en el seis.','Proponer DAN=5 en H6 y pedir confirmación de sobreescritura.'),
('Oyes completo','H7, par 3. Sin ranking previo.','Oyes del siete: primero Ricardo, segundo Anselmo, tercero Daniel, cuarto Roberto y quinto Fernando.','Ranks H7: RIC=1, ANS=2, DAN=3, ROB=4, FER=5.'),
('Oyes alias','H16, par 3.','O yes: Richi primero, Dani segundo, Anse tercero, Bob cuarto y Fernando quinto.','Ranks H16: RIC=1, DAN=2, ANS=3, ROB=4, FER=5. Variante de voz.'),
('Oyes parcial','H7, par 3.','El oyes lo ganó Anselmo.','ANS rank=1. No inventar otras posiciones; consultar si falta orden para resolver apuestas.'),
('Oyes duplicado','H7, par 3.','Primero Daniel y primero Ricardo en los oyes.','No guardar ranking conflictivo. Preguntar quién es primero o aclarar empate según regla.'),
('Oyes fuera de par 3','H6, par 5.','Ricardo ganó el oyes en el seis.','Señalar incompatibilidad de hoyo y pedir aclaración; no cambiar el par.'),
('Tripoteo','H6. Unidades 3P habilitadas para prueba.','Roberto hizo seis y tripoteó.','ROB golpes=6, putts=3; registrar 3P una vez según regla activa.'),
('Cuatripoteo','H8. Caso de vocabulario, sin regla 4P confirmada.','Fernando cinco y cuatripoteo.','FER golpes=5, putts=4. No inventar valor monetario ni unidad 4P.'),
('Hole out','H8. HO habilitado para prueba.','Daniel hizo cuatro y hole out.','DAN golpes=4; evento HO para DAN, H8. Monetización solo según configuración.'),
('Dicho nuevo','H8. Sandy no confirmado en catálogo activo.','Anselmo hizo sandy y Ricardo chip in.','Extraer candidatos Sandy=ANS y Chip-in=RIC. Pedir regla/configuración; no monetizar automáticamente.'),
('Frase mixta','H7, par 3. OYES y HO habilitados.','Yo tres, Anselmo cuatro y los demás bogey. Oyes primero Ricardo, segundo Daniel, tercero Fernando, cuarto Anselmo, quinto Roberto. Daniel hole out.','DAN=3; ANS=ROB=RIC=FER=4. Ranks RIC=1,DAN=2,FER=3,ANS=4,ROB=5. HO DAN una vez.'),
('Falta jugador','H6, par 5.','Hizo cinco y dos putts.','Preguntar qué jugador. No asignar a yo ni a todos.'),
('Seguimiento de audit','Salida H10. Llegamos a H11, par 3 de escenario. Golpes completos; putts desactivados; oyes sin registrar.','Ya terminamos el once.','No inventar golpes ni ranking. Recordar oyes pendiente H11. Seguir orden H10...H18,H1...H9.')
]
records=[dict(id=f'C{i:02}',title=t,context=ctx,utterance=u,expected=e,players={'DAN':'Daniel','ANS':'Anselmo','ROB':'Roberto','RIC':'Ricardo','FER':'Fernando'}) for i,(t,ctx,u,e) in enumerate(cases,1)]
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'casos_dictado.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
W,H=612,792
def lines(c,text,x,y,width,size=11,leading=16):
 c.setFont('Helvetica',size)
 for line in simpleSplit(text,'Helvetica',size,width): c.drawString(x,y,line); y-=leading
 return y
def header(c,title,page):
 c.setFillColor(HexColor('#22613c'));c.setFont('Helvetica-Bold',19);c.drawString(36,754,title)
 c.setFillColor(HexColor('#333333'));c.setFont('Helvetica',9);c.drawString(36,22,f'Caddy Dicta | Corpus v1 | 05 oct 2026 | {page}')
c=canvas.Canvas(str(OUT/'tarjetas_dictado_campo.pdf'),pagesize=(W,H))
header(c,'Guía de grabación en campo',1)
y=707
instructions=[
'Objetivo: reunir audio real y respuestas correctas para evaluar y mejorar la voz. Estas tarjetas no acreditan funciones ya implementadas.',
'Jugadores de prueba: DAN Daniel, ANS Anselmo, ROB Roberto, RIC Ricardo y FER Fernando. Son cinco jugadores. Por defecto yo = DAN; C06 cambia a RIC.',
'Los hoyos y pares de cada tarjeta son escenarios sintéticos. No representan necesariamente el campo CGM. Cada caso comienza con su propio contexto.',
'Con permiso de cada participante, asigna un código V01, V02... No hace falta guardar su nombre. No incluyas conversaciones de terceros.',
'Antes de cada toma, el coordinador prepara o anuncia el contexto. El lector dice el ID y después lee solamente la frase entre comillas. El ID no forma parte de la orden a interpretar.',
'Graba cada caso por separado: C02_V01_campo_T01.m4a. Conserva el audio original. Haz una toma natural; repite otra con tus propios dichos, sin forzar ni imitar acentos.',
'Repite con varias personas. Registra silencio, viento o conversación ambiental, dispositivo, fecha y distancia aproximada al micrófono. Evita colocar el reloj junto a la boca si no sería tu uso normal.',
'No uses estas pruebas para modificar una ronda real. Usa una ronda de prueba o una grabadora. Las tarjetas se recortan por las líneas; imprime Carta al 100%, a una cara.',
'Oyes y unidades: las reglas activas de la ronda mandan. HO y 3P se habilitan solo en casos indicados. Sandy, chip-in y 4P requieren validación adicional; no tienen valor monetario supuesto.',
'Entrega los audios y la bitácora. La clave del coordinador contiene lo esperado. Reserva voces y sesiones completas para evaluación: no ajustes el diccionario con todos los audios y luego pruebes con los mismos.'
]
for s in instructions:y=lines(c,s,36,y,540,11,16)-16
c.showPage()
for page in range(6):
 header(c,'Tarjetas para leer en voz alta',page+2)
 for j,r in enumerate(records[page*4:page*4+4]):
  top=720-j*171;c.setStrokeColor(HexColor('#bbbbaa'));c.rect(36,top-157,540,157)
  c.setFont('Helvetica-Bold',13);c.drawString(48,top-23,r['id']+' | '+r['title'])
  y=lines(c,'Contexto: '+r['context'],48,top-43,516,9,12)-12
  y=lines(c,'“'+r['utterance']+'”',48,y,516,13,18)
  c.setFont('Helvetica',9);c.drawString(48,top-145,'Voz: ______  Toma: ____  Ruido: __________  Audio: __________________')
 c.showPage()
c.save()
k=canvas.Canvas(str(OUT/'clave_y_bitacora.pdf'),pagesize=(W,H))
for page in range(6):
 header(k,'Clave del coordinador',page+1)
 for j,r in enumerate(records[page*4:page*4+4]):
  y=714-j*165;k.setFont('Helvetica-Bold',12);k.drawString(36,y,r['id']+' | '+r['title'])
  lines(k,r['expected'],36,y-23,540,11,16)
 k.showPage()
header(k,'Bitácora de grabaciones',7)
lines(k,'Voz: ____  Fecha: ____  Dispositivo: ____  Entorno: ____  Permiso: sí / no',36,709,540)
lines(k,'Anota transcripción real, cambio de frase y error. No alteres la respuesta esperada para ocultar un fallo.',36,680,540)
for i in range(9):
 y=629-i*62;k.setFont('Helvetica',10);k.drawString(36,y,'Caso: ____  Toma: ____  Archivo: __________________  Correcto: sí / no')
 k.drawString(36,y-23,'Frase / observación: _____________________________________________________')
k.showPage();k.save()
print('24 casos; tarjetas 7 páginas; clave y bitácora 7 páginas')
targets=[
('DAN = 5 golpes','H6, par 5. Yo = DAN.',['Daniel cinco.','Dani hizo cinco golpes.','Tiré cinco.','Yo hice par.']),
('RIC = 6 golpes','H6, par 5. Yo = DAN.',['Ricardo seis.','Richi hizo seis golpes.','Ricardo hizo bogey.','Anota seis a Ricardo.']),
('ANS = 4 golpes','H8, par 4.',['Anselmo cuatro.','Anse hizo cuatro golpes.','Anselmo hizo par.','Ponle cuatro a Anselmo.']),
('ROB = 7 golpes','H6, par 5.',['Roberto siete.','Bob hizo siete golpes.','Roberto doble bogey.','Anota siete a Roberto.']),
('FER = 3 golpes','H7, par 3.',['Fernando tres.','Fer hizo tres golpes.','Fernando hizo par.','Ponle tres a Fernando.']),
('DAN = 5; los otros cuatro = 6','H6, par 5. Yo = DAN.',['Tiré cinco y los demás bogey.','Yo par y todos los demás seis.','Daniel cinco, Anselmo seis, Roberto seis, Ricardo seis y Fernando seis.']),
('RIC primero en oyes','H7, par 3. Sin ranking previo.',['Ricardo ganó el oyes.','El oyes fue de Richi.','Ricardo quedó primero en oyes.','El más cerca fue Ricardo.']),
('Orden de oyes completo','H7, par 3. RIC 1, ANS 2, DAN 3, ROB 4, FER 5.',['Oyes: Ricardo primero, Anselmo segundo, Daniel tercero, Roberto cuarto y Fernando quinto.','Primero Richi, segundo Anse, tercero Dani, cuarto Bob y quinto Fer en los oyes.']),
('ROB = 3 putts','H6. 3P habilitado para esta prueba.',['Roberto tres putts.','Bob tripoteó.','Roberto hizo tripoteo.','Anota tres putts a Roberto.']),
('FER = 4 putts','H8. Sin unidad monetaria 4P definida.',['Fernando cuatro putts.','Fer cuatripoteó.','Fernando hizo cuatripoteo.']),
('HO para DAN','H8. Hole Out habilitado en esta prueba.',['Daniel hizo hole out.','Dani hole out.','Anota hole out a Daniel.']),
('DAN birdie: 4 golpes, evento BIRD una vez','H6, par 5. Birdie calculado desde bruto.',['Daniel birdie.','Dani hizo cuatro golpes.','Daniel hizo uno abajo del par.','Anota birdie a Daniel.'])
]
pdf=canvas.Canvas(str(OUT/'tarjetas_objetivo_grabacion.pdf'),pagesize=(W,H))
header(pdf,'Tarjetas por objetivo | Grabación',1)
y=706
for paragraph in [
'12 tarjetas. Cada tarjeta fija el dato correcto. Cada frase es una toma independiente: reinicia el contexto entre frases; no sumes registros repetidos.',
'Jugadores: Daniel DAN, Anselmo ANS, Roberto ROB, Ricardo RIC y Fernando FER. Los pares son escenarios de prueba. Prepara ese contexto antes de interpretar.',
'En el iPhone usa Notas de Voz: inicia una grabación, lee tarjeta y frase, detén y cambia el nombre. Ejemplo: T01_F02_V01.m4a (tarjeta 1, frase 2, voz 1).',
'Graba las frases literalmente una vez; luego otra toma con un dicho natural tuyo y anótalo. Conserva el audio original y registra si hubo viento o ruido.',
'El objetivo y el contexto son para el coordinador; el participante lee solamente la frase. Si anuncia los identificadores, haz una pausa y sepáralos antes de probar el reconocimiento.',
'Oyes ganador no implica inventar el resto del ranking. Las unidades solo se aplican si están habilitadas; birdie no se registra dos veces por dictarlo y calcularlo.',
'Con permiso de los participantes, usa códigos V01, V02... Comparte después los archivos originales mediante Compartir de Notas de Voz. Guarda este PDF en Archivos para imprimirlo o consultarlo.',
'Imprime Carta al 100%, a una cara. Recorta las tarjetas. No ejecutes las pruebas sobre una ronda real. Esto prepara una base de audio etiquetada; todavía no entrena automáticamente un modelo.'
]:y=lines(pdf,paragraph,36,y,540,12,18)-18
pdf.showPage()
dataset=[]
for page in range(6):
 header(pdf,'Leer cada frase por separado',page+2)
 for j,(target,ctx,phrases) in enumerate(targets[page*2:page*2+2]):
  number=page*2+j+1;top=714-j*335
  pdf.setStrokeColor(HexColor('#bbbbaa'));pdf.rect(36,top-315,540,315)
  pdf.setFont('Helvetica-Bold',15);pdf.drawString(48,top-25,f'T{number:02} | Objetivo')
  yy=lines(pdf,target,48,top-50,516,13,18)-10
  yy=lines(pdf,'Contexto: '+ctx,48,yy,516,10,15)-17
  for f,phrase in enumerate(phrases,1):
   yy=lines(pdf,f'F{f:02}. "{phrase}"',48,yy,516,13,20)-9
   dataset.append(dict(id=f'T{number:02}_F{f:02}',target=target,context=ctx,utterance=phrase))
  pdf.setFont('Helvetica',10);pdf.drawString(48,top-296,'Voz: ______  Fecha: ______  Entorno / ruido: __________________')
 pdf.showPage()
pdf.save()
(OUT/'objetivos_grabacion.json').write_text(json.dumps(dataset,ensure_ascii=False,indent=2))
print('Tarjetas por objetivo: 7 páginas,',len(dataset),'frases etiquetadas')
