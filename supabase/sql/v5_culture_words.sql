-- supabase/sql/v5_culture_words.sql
--
-- v5.0 — the words the machine keeps getting wrong, written down once.
--
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Safe to re-run: every row is `on conflict do update`.
--
-- "шаңырақ" reached a learner as "shangri-la". "бауырсақ" came back as
-- "butterfly". These are not random failures — they are all the same kind of
-- word: culturally specific Kazakh nouns that the models have the least
-- training data for and that the keyless services have none at all. Every
-- safeguard in the edge function fires correctly on them and the learner is
-- told there is no translation, which is honest but useless.
--
-- A dictionary is allowed to just KNOW things. These rows are marked verified,
-- so the lookup returns them instantly, no model is asked, no quota is spent,
-- and a moderator's correction outranks anything an AI would have said.
--
-- Where English genuinely borrowed the word (dombra, kumis, yurt) that IS the
-- English, and the transliteration gate's loanword check is what distinguishes
-- those from an invented respelling.

-- en_key / kk_key / ru_key are normally filled by dict_upsert, and nothing
-- fills them on a plain INSERT — so they are computed here with the same
-- norm_term() the lookup uses. Without them the row exists and can never be
-- found.
with seed(en, kk, ru, pos, definition_en, synonyms, antonyms,
          example_en, example_kk, ipa, emoji, cefr, topic) as (
values
  ('yurt crown', 'шаңырақ', 'шанырак', 'noun',
   'The round wooden crown at the top of a yurt; a symbol of home and family.',
   array['crown of the yurt', 'roof ring', 'home'], array[]::text[],
   'The yurt crown lets light and smoke through the roof.',
   'Шаңырақ шатырдан жарық пен түтінді өткізеді.',
   '/jɜːrt kraʊn/', '🏕️', 'B1', 'home'),

  ('dombra', 'домбыра', 'домбра', 'noun',
   'A two-stringed Kazakh lute played by plucking.',
   array['lute', 'string instrument'], array[]::text[],
   'He played an old melody on the dombra.',
   'Ол домбырада ескі күй тартты.',
   '/ˈdɒmbrə/', '🪕', 'A2', 'general'),

  ('baursak', 'бауырсақ', 'баурсак', 'noun',
   'Small pieces of dough deep-fried in oil, served with tea.',
   array['fried dough', 'doughnut'], array[]::text[],
   'She served hot baursak with tea.',
   'Ол шайға ыстық бауырсақ әкелді.',
   '/ˈbaʊərsɑːk/', '🍩', 'A2', 'food'),

  ('kumis', 'қымыз', 'кумыс', 'noun',
   'A drink of fermented mare''s milk.',
   array['fermented milk', 'mare''s milk'], array[]::text[],
   'Kumis is served cold in summer.',
   'Қымыз жазда салқын күйінде беріледі.',
   '/ˈkuːmɪs/', '🥛', 'B1', 'food'),

  ('yurt', 'киіз үй', 'юрта', 'noun',
   'A round felt tent used by nomads.',
   array['nomad tent', 'felt tent'], array['house'],
   'The family put up a yurt beside the river.',
   'Отбасы өзен жағасына киіз үй тікті.',
   '/jɜːrt/', '🏕️', 'A2', 'home'),

  ('beacon', 'шамшырақ', 'маяк', 'noun',
   'A light used as a signal or a guide.',
   array['lighthouse', 'signal light', 'guiding light'], array['darkness'],
   'The lighthouse was a beacon for the ships.',
   'Шамшырақ кемелерге жол көрсетті.',
   '/ˈbiːkən/', '🔦', 'B1', 'general'),

  ('knucklebone', 'асық', 'асык', 'noun',
   'A small animal ankle bone used as a piece in a traditional game.',
   array['ankle bone', 'game piece'], array[]::text[],
   'Children play a game with knucklebones.',
   'Балалар асық ойнайды.',
   '/ˈnʌkəlboʊn/', '🎲', 'B1', 'sport'),

  ('first steps ceremony', 'тұсаукесер', 'тусаукесер', 'noun',
   'A celebration held when a small child first walks.',
   array['first walk celebration', 'walking ceremony'], array[]::text[],
   'The family held a first steps ceremony for the baby.',
   'Отбасы нәрестеге тұсаукесер жасады.',
   '/fɜːrst steps ˈserəmoʊni/', '👣', 'B2', 'family'),

  ('cradle', 'бесік', 'колыбель', 'noun',
   'A small bed for a baby, often able to rock.',
   array['crib', 'cot', 'bassinet'], array[]::text[],
   'The baby slept soundly in the cradle.',
   'Нәресте бесікте тәтті ұйықтады.',
   '/ˈkreɪdəl/', '👶', 'A2', 'family'),

  ('low table', 'дастархан', 'дастархан', 'noun',
   'A spread table of food, and the gathering around it.',
   array['spread', 'feast table'], array[]::text[],
   'Guests gathered around the low table.',
   'Қонақтар дастархан басына жиналды.',
   '/loʊ ˈteɪbəl/', '🍽️', 'B1', 'food'),

  ('bowl', 'кесе', 'пиала', 'noun',
   'A small round cup without a handle, used for tea.',
   array['cup', 'tea bowl'], array[]::text[],
   'She poured tea into a small bowl.',
   'Ол кесеге шай құйды.',
   '/boʊl/', '🍵', 'A1', 'food'),

  ('summer pasture', 'жайлау', 'джайлау', 'noun',
   'High grassland where herds are taken to graze in summer.',
   array['highland pasture', 'grazing land'], array[]::text[],
   'The herds move to the summer pasture in June.',
   'Мал маусымда жайлауға көшеді.',
   '/ˈsʌmər ˈpæstʃər/', '⛰️', 'B1', 'nature'),

  ('amulet', 'тұмар', 'оберег', 'noun',
   'A small object worn to keep a person from harm.',
   array['charm', 'talisman'], array[]::text[],
   'She wore an amulet on a thin cord.',
   'Ол мойнына тұмар тақты.',
   '/ˈæmjələt/', '🧿', 'B2', 'general'),

  ('felt rug', 'сырмақ', 'сырмак', 'noun',
   'A patterned rug made of stitched felt.',
   array['felt carpet', 'rug'], array[]::text[],
   'A felt rug covered the floor of the yurt.',
   'Киіз үйдің еденін сырмақ жапты.',
   '/felt rʌɡ/', '🧶', 'B2', 'home'),

  ('shepherd', 'шопан', 'пастух', 'noun',
   'A person who looks after sheep.',
   array['herder', 'sheep keeper'], array[]::text[],
   'The shepherd led the flock down the hill.',
   'Шопан отарды төмен қарай айдады.',
   '/ˈʃepərd/', '🐑', 'A2', 'work'),

  ('eagle hunter', 'бүркітші', 'беркутчи', 'noun',
   'A hunter who hunts with a trained golden eagle.',
   array['falconer', 'eagle master'], array[]::text[],
   'The eagle hunter rode out at dawn.',
   'Бүркітші таң ата жолға шықты.',
   '/ˈiːɡəl ˈhʌntər/', '🦅', 'B2', 'work'),

  ('naked', 'жалаңаш', 'голый', 'adjective',
   'Without clothes or covering.',
   array['bare', 'unclothed', 'nude'], array['dressed', 'clothed'],
   'He ran to the water with naked feet.',
   'Ол суға жалаңаш аяқ жүгірді.',
   '/ˈneɪkɪd/', '👣', 'B1', 'body'),

  ('library', 'кітапхана', 'библиотека', 'noun',
   'A building or room where books are kept and borrowed.',
   array['reading room', 'book collection'], array[]::text[],
   'I go to the library to study.',
   'Мен кітапханаға оқуға барамын.',
   '/ˈlaɪbreri/', '📚', 'A2', 'school'),

  ('teacher', 'мұғалім', 'учитель', 'noun',
   'A person whose job is to teach.',
   array['tutor', 'instructor', 'educator'], array['student'],
   'Our teacher explained the rule twice.',
   'Мұғаліміміз ережені екі рет түсіндірді.',
   '/ˈtiːtʃər/', '👩‍🏫', 'A1', 'school'),

  ('cheese', 'ірімшік', 'сыр', 'noun',
   'A food made from pressed milk curds.',
   array['curd cheese', 'dairy'], array[]::text[],
   'She cut the cheese into small pieces.',
   'Ол ірімшікті ұсақтап турады.',
   '/tʃiːz/', '🧀', 'A1', 'food')
)
insert into public.dictionary
  (en_key, kk_key, ru_key, en, kk, ru, pos, definition_en, synonyms, antonyms,
   example_en, example_kk, ipa, emoji, cefr, topic, source, verified)
select public.norm_term(s.en), public.norm_term(s.kk), public.norm_term(s.ru),
       s.en, s.kk, s.ru, s.pos, s.definition_en, s.synonyms, s.antonyms,
       s.example_en, s.example_kk, s.ipa, s.emoji, s.cefr, s.topic, 'seed', true
from seed s
on conflict (en_key) do update
  set kk            = excluded.kk,
      kk_key        = excluded.kk_key,
      ru            = excluded.ru,
      ru_key        = excluded.ru_key,
      pos           = excluded.pos,
      definition_en = excluded.definition_en,
      synonyms      = excluded.synonyms,
      antonyms      = excluded.antonyms,
      example_en    = excluded.example_en,
      example_kk    = excluded.example_kk,
      ipa           = excluded.ipa,
      emoji         = excluded.emoji,
      cefr          = excluded.cefr,
      topic         = excluded.topic,
      -- A hand-written row outranks whatever the AI stored here before.
      verified      = true;
