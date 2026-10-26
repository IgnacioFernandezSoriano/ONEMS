-- 2026-10-26: accounts.timezone only accepted 13 fixed zones, none in Africa, so KENYA and Senegal had to stay on UTC
-- and the bot's "today" for them started at 03:00 local time in Nairobi. Keep the 13 zones and add one IANA zone per
-- African country (two for DR Congo), all checked against pg_timezone_names.

ALTER TABLE public.accounts DROP CONSTRAINT IF EXISTS accounts_valid_timezone;

ALTER TABLE public.accounts ADD CONSTRAINT accounts_valid_timezone CHECK (timezone = ANY (ARRAY[
  -- original zones
  'UTC', 'Europe/Madrid', 'Europe/London', 'Europe/Paris', 'America/New_York', 'America/Los_Angeles',
  'America/Mexico_City', 'America/Sao_Paulo', 'America/Buenos_Aires', 'Asia/Tokyo', 'Asia/Shanghai', 'Asia/Dubai',
  'Australia/Sydney',
  -- Africa
  'Africa/Abidjan', 'Africa/Accra', 'Africa/Addis_Ababa', 'Africa/Algiers', 'Africa/Asmara', 'Africa/Bamako',
  'Africa/Bangui', 'Africa/Banjul', 'Africa/Bissau', 'Africa/Blantyre', 'Africa/Brazzaville', 'Africa/Bujumbura',
  'Africa/Cairo', 'Africa/Casablanca', 'Africa/Conakry', 'Africa/Dakar', 'Africa/Dar_es_Salaam', 'Africa/Djibouti',
  'Africa/Douala', 'Africa/El_Aaiun', 'Africa/Freetown', 'Africa/Gaborone', 'Africa/Harare', 'Africa/Johannesburg',
  'Africa/Juba', 'Africa/Kampala', 'Africa/Khartoum', 'Africa/Kigali', 'Africa/Kinshasa', 'Africa/Lagos',
  'Africa/Libreville', 'Africa/Lome', 'Africa/Luanda', 'Africa/Lubumbashi', 'Africa/Lusaka', 'Africa/Malabo',
  'Africa/Maputo', 'Africa/Maseru', 'Africa/Mbabane', 'Africa/Mogadishu', 'Africa/Monrovia', 'Africa/Nairobi',
  'Africa/Ndjamena', 'Africa/Niamey', 'Africa/Nouakchott', 'Africa/Ouagadougou', 'Africa/Porto-Novo',
  'Africa/Sao_Tome', 'Africa/Tripoli', 'Africa/Tunis', 'Africa/Windhoek',
  'Atlantic/Cape_Verde', 'Indian/Antananarivo', 'Indian/Comoro', 'Indian/Mahe', 'Indian/Mauritius'
]::text[]));
