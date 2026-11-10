# Bot de análisis de casos para los managers de cada cuenta

**Fecha:** 2026-11-10 (sesión), documento 2026-11-11
**Estado:** borrador para revisión del usuario
**Amplía:** `2026-11-10-agente-analisis-de-casos-design.md` y `2026-11-10-agente-casos-tarjeta-y-aplicar-design.md`. Todo lo que aquí no se contradice sigue vigente.

---

## 1. Intención

Hoy solo Ignacio puede analizar casos, desde su chat privado con el bot del agente («Panelist App Monitoring»). Se quiere que **los managers de cada cuenta gestionen sus propios casos** desde un bot nuevo, en un chat privado: analizar, enviar los mensajes a sus panelistas y aplicar los arreglos sencillos de su cuenta.

El control no se hace aprobando a cada persona ni limitando el número de consultas: se hace **por dinero**. Cada análisis se apunta a su cuenta y hay un tope mensual en dólares por cuenta.

## 2. Decisiones del usuario

- **Bot nuevo** («Panelist Event Analysis Bot»), distinto del de Ignacio. Cada manager habla con él **en privado**. No hay grupo.
- **Sin aprobación previa.** Quien tenga el bot puede usarlo. Ignacio solo da el nombre del bot a quien él decide.
- **Identificación por correo.** La primera vez, el bot pide el correo de ONEMS y envía un código a ese correo. Al escribir el código, la persona queda unida a su cuenta.
- **Gestión por cuenta.** Cada manager analiza, envía mensajes y aplica arreglos **solo en su cuenta**.
- **Sin límite de consultas.** El control es el gasto: **tope de 5 $ al mes por cuenta**. Ignacio ve lo gastado por cuenta y por persona.
- **El bot de Ignacio sigue igual:** informe de las 8:00, arreglos de n8n y análisis de cualquier cuenta.

## 3. Objetivos

1. **Alta del manager:**
   - Sin identificar, el bot solo contesta: «Escríbeme tu correo de ONEMS para empezar».
   - Con un correo válido (§4), envía un código de 6 cifras por correo (Resend, el mismo canal del informe de operación), válido 15 minutos.
   - Con el código bueno, guarda la unión entre el id de Telegram, el correo, la cuenta y el rol, y saluda: «Listo: estás en la cuenta X como Y».
   - Máximo 5 intentos de código; después hay que pedir uno nuevo.
2. **Uso.** Igual que el análisis de casos de Ignacio:
   - el manager reenvía capturas o mensajes, escribe el nombre si hace falta y pulsa «Analizar»;
   - recibe la tarjeta Problema / Causa / Solución con «Ver detalle», «Enviar» en cada borrador, «Aplicar» si R4 aplica, o «Prompt para Claude Code».
   - Todo queda limitado a su cuenta:
     - los candidatos a panelista solo salen de su cuenta;
     - si el caso es de otra cuenta, el bot responde «Ese caso no es de tu cuenta» y no lo analiza;
     - envío y R4 solo sobre panelistas e incidencias de su cuenta.
3. **Gasto:**
   - cada llamada a la IA del análisis se apunta con la cuenta y la persona;
   - al alcanzar 5 $ en el mes natural, el bot contesta «Tu cuenta ha llegado al límite de este mes» y no llama a la IA hasta el día 1;
   - en el bot de Ignacio, la orden «gastos» muestra el mes en curso por cuenta y por persona;
  - en el bot de managers, «gastos» muestra al manager lo que lleva su cuenta este mes y su parte (petición de Ignacio del 2026-11-11), y al pasar del 80 % del tope se avisa una vez;
   - el tope global del agente (`monthly_cap_eur`) sigue funcionando por encima de todo.
4. **Registro.** Cada análisis, mensaje y arreglo hecho por un manager queda en la incidencia o el caso como hoy. La nota indica quién lo hizo: «analizado por <correo>».

## 4. Quién puede darse de alta

- **Correos válidos:** solo los guardados en la ficha de la cuenta en ONEMS (`accounts`) para estos roles:
  - `email_panelist_manager` (gestor de panelistas);
  - `email_account_manager` (account manager);
  - `email_allocation_plan_manager` (Allocation Plan Manager, rol nuevo: ver §9).
- **Superadmin:** además, cualquier superadmin de ONEMS, que elige el país (§9).
- **Altas y bajas:** Ignacio da acceso o lo quita cambiando esos correos en ONEMS, sin tocar el bot.
- **Comprobación continua:** en cada uso, el bot comprueba que el correo de la persona siga siendo uno de esos roles de su cuenta. Si ya no lo es, le pide que se identifique de nuevo.
- **Cuentas fuera:** las de prueba (`report.excluded_accounts`) no se admiten, salvo DEMO2, para las pruebas.

## 5. No-objetivos

- Que los managers reciban el informe de las 8:00 o toquen n8n.
- Un panel en ONEMS para gestionar accesos o gastos (de momento, la orden «gastos»).
- Límites por número de consultas.

## 6. Anti-objetivos

- Que alguien sin identificar gaste dinero. La IA no se llama antes del alta.
- Que un manager vea o toque datos de otra cuenta.
- Que el código de alta o el correo aparezcan en los registros.
- Que un panelista use el bot. Si un panelista lo encuentra, no podrá darse de alta, porque su correo no es de un rol de la cuenta.

## 7. Restricciones

- **Mismo agente y servidor (Hetzner):**
  - el bot nuevo es un segundo token de Telegram (`MANAGER_BOT_TOKEN`) que Ignacio pondrá en su propio fichero de entorno, `/etc/onems-ops-agent/manager.env`, junto con `MANAGER_OPS_TOKEN` (el token de la base para los managers); no van en `/etc/onems-ops-agent/env`, que es solo del bot de Ignacio;
  - un servicio propio (`onems-ops-agent-managerbot.service`) que corre con su propio usuario Unix (`opsmgr`, sin login ni home): no puede leer `env` ni los ficheros privados del bot de Ignacio, y solo comparte con él la base local del agente (`agent.db`, por un grupo común).
- **Base onems-dev `sehbnpgzqljrsqimwyuz`:**
  - si hacen falta funciones nuevas (comprobar si un correo es de un rol de una cuenta), siguen el patrón de token (`ops_*`, anon + token);
  - migración con confirmación de Ignacio.
- **Datos del agente:**
  - las altas (`telegram_id → correo, cuenta, rol, fecha`), los códigos pendientes (con hash, nunca en claro) y el gasto por cuenta y persona van en la base local del agente (SQLite);
  - el gasto de lo que piden los managers desde ONEMS sigue contando para su cuenta.
- **Reutilización:** se usa la lógica de análisis ya hecha (`case_bot`, `case_analysis`, `case_fix_buttons`), parametrizada por «quién pregunta y de qué cuenta», sin duplicarla.
- **Envíos a panelistas:** `case.send_accounts` (hoy solo DEMO2) sigue mandando. Una cuenta sin permiso de envío deja analizar pero no enviar, hasta que Ignacio la abra.
- **Idioma:** la interfaz del bot para managers va en el idioma de su cuenta (`accounts.default_language`), con los 4 o 5 idiomas del proyecto.

## 8. Se deja al builder

- Un proceso con dos bots o dos servicios systemd.
- El texto exacto de los mensajes y del correo con el código.
- El formato de la orden «gastos».
- Cómo se cuenta el gasto de los análisis pedidos desde ONEMS: el agente ya sabe la cuenta de la petición.

## 9. Decidido por Ignacio tras la revisión

- **Rol nuevo «Allocation Plan Manager».**
  - La ficha de la cuenta gana el correo `email_allocation_plan_manager`, con el mismo formato y la misma validación que los otros roles.
  - La pantalla de la cuenta en ONEMS gana ese campo, con el texto en los 5 idiomas.
  - Los roles que dan acceso al bot son: Panelist Manager, Account Manager y Allocation Plan Manager.
- **Una persona, un país.**
  - Si un correo aparece en varias cuentas y no es de un superadmin, el bot no lo da de alta: «Tu correo está en varias cuentas; pide al responsable que lo corrija en ONEMS».
  - El país se decide en ONEMS: el correo se deja solo en la cuenta que toca.
- **Superadmin.**
  - Un usuario con perfil `superadmin` en ONEMS (por correo) puede trabajar con cualquier país.
  - Al darse de alta elige el país, y puede cambiarlo cuando quiera con una orden («país»).
  - Todo lo que hace (análisis, envíos, arreglos y gasto) va contra el país elegido en ese momento.

## 9b. Decisiones tras la revisión del builder (mías, revisables)

- **Varios managers a la vez.** Las cajas de casos, el «Cambiar» pendiente y el «analizando» van por chat, no globales. Esto obliga a ajustar `store.py` y `case_bot.py` para guardar el chat en cada caso. Un manager nunca ve ni bloquea lo de otro.
- **La cuenta la comprueba la base.**
  - Las funciones `ops_case_find_panelists`, `ops_case_data`, `ops_case_send` y `ops_fix_r4_*` reciben la cuenta del manager y rechazan lo que sea de otra.
  - Si el nombre solo coincide con panelistas de otra cuenta, el bot contesta como si no hubiera candidatos («No encuentro a ese panelista en tu cuenta»), para no revelar que existe en otro país.
  - Cada botón vuelve a comprobar que el resultado guardado es de la cuenta y del chat de quien lo pulsa.
- **Gasto:**
  - se comprueba antes de cada análisis y de cada «Cambiar»: si la cuenta ya ha llegado al tope, no se llama a la IA;
  - un análisis empezado se termina aunque pase un poco del tope;
  - cuenta todo: lectura de capturas, análisis, redacciones y casos rechazados por ser de otra cuenta;
  - el mes natural es el de Madrid, igual que el resto del agente;
  - el gasto de los análisis pedidos desde ONEMS se apunta a la cuenta de la incidencia.
- **Abuso del código de alta:**
  - máximo 3 códigos por hora por chat de Telegram y por correo;
  - la respuesta es la misma tanto si el correo es válido como si no («Si el correo es de un responsable de una cuenta, recibirás un código»);
  - el remitente es el mismo de Resend que el informe de operación.
- **Comprobación del rol:** el resultado se guarda 5 minutos. Si se quita el correo en ONEMS, el alta se bloquea, pero no se borra, para que quede rastro.
- **Prompt para Claude Code:** no se muestra a los managers, solo a Ignacio y a los superadmin.
- **Cuentas abiertas.** Se usan las mismas puertas que ahora:
  - durante las pruebas, solo DEMO2 analiza, envía y aplica arreglos;
  - Ignacio abre las demás cuentas cuando decida, con una migración para el análisis desde ONEMS y en `case.send_accounts` del agente para los envíos;
  - en una cuenta todavía cerrada, el bot dice «Tu cuenta aún no tiene el análisis activado».

## 10. Aceptación

- Con DEMO2:
  - el alta por correo y código funciona;
  - el manager analiza el caso de prueba, envía el mensaje a PAN-DEM-003 y aplica y deshace R4;
  - un caso de otra cuenta se rechaza;
  - con el tope bajado a 0,01 $, el bot avisa del límite y no llama a la IA.
- Sin alta, ningún mensaje genera gasto.
- La orden «gastos» del bot de Ignacio muestra lo de DEMO2.
