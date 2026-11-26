-- Fichier généré par tool/generate_seed.dart depuis assets/questions.json.
-- Ne pas modifier à la main : relancer `dart run tool/generate_seed.dart`.
-- Appliqué par `supabase db reset` (local) ou `supabase db push --include-seed`.

insert into public.questions
  (id, category, difficulty, question, answers, correct_index, explanation)
values
  ('his-001', 'histoire', 1, 'En quelle année a eu lieu la prise de la Bastille ?', array['1789', '1792', '1776', '1804'], 0, 'La Bastille a été prise le 14 juillet 1789, date devenue la fête nationale française.'),
  ('his-002', 'histoire', 1, 'Qui a été le premier président de la Ve République ?', array['Charles de Gaulle', 'Georges Pompidou', 'René Coty', 'François Mitterrand'], 0, 'Charles de Gaulle a été élu en décembre 1958 et a pris ses fonctions en janvier 1959. René Coty était le dernier président de la IVe République.'),
  ('his-003', 'histoire', 1, 'En quelle année le mur de Berlin est-il tombé ?', array['1989', '1991', '1985', '1961'], 0, 'Le mur est tombé le 9 novembre 1989. Il avait été construit en 1961.'),
  ('geo-001', 'geo', 2, 'Quelle est la capitale de l''Australie ?', array['Canberra', 'Sydney', 'Melbourne', 'Perth'], 0, 'Canberra a été choisie comme capitale, en compromis entre Sydney et Melbourne.'),
  ('geo-002', 'geo', 1, 'Quel est le plus long fleuve de France ?', array['La Loire', 'La Seine', 'Le Rhône', 'La Garonne'], 0, 'La Loire mesure environ 1 000 km et coule entièrement en France.'),
  ('geo-003', 'geo', 1, 'Quel est le plus grand océan du monde ?', array['L''océan Pacifique', 'L''océan Atlantique', 'L''océan Indien', 'L''océan Arctique'], 0, 'Le Pacifique couvre environ un tiers de la surface de la Terre.'),
  ('sci-001', 'sciences', 1, 'Quel est le symbole chimique de l''or ?', array['Au', 'Ag', 'Or', 'Go'], 0, 'Au vient du latin « aurum ». Ag est le symbole de l''argent.'),
  ('sci-002', 'sciences', 1, 'Combien de planètes compte le système solaire ?', array['8', '9', '7', '10'], 0, 'Depuis 2006, Pluton est classée planète naine : il reste 8 planètes.'),
  ('sci-003', 'sciences', 2, 'Quel gaz est le plus abondant dans l''atmosphère terrestre ?', array['L''azote', 'L''oxygène', 'Le dioxyde de carbone', 'L''argon'], 0, 'L''azote représente environ 78 % de l''air, l''oxygène environ 21 %.'),
  ('art-001', 'arts', 1, 'Qui a peint La Joconde ?', array['Léonard de Vinci', 'Michel-Ange', 'Raphaël', 'Botticelli'], 0, 'Léonard de Vinci l''a peinte au début du XVIe siècle. Elle est exposée au Louvre.'),
  ('art-002', 'arts', 1, 'Qui a écrit Les Misérables ?', array['Victor Hugo', 'Émile Zola', 'Honoré de Balzac', 'Alexandre Dumas'], 0, 'Victor Hugo a publié Les Misérables en 1862.'),
  ('art-003', 'arts', 2, 'Combien de symphonies Beethoven a-t-il composées ?', array['9', '5', '12', '7'], 0, 'Beethoven a composé 9 symphonies. La 9e contient l''« Ode à la joie », hymne de l''Union européenne.'),
  ('spo-001', 'sport', 1, 'Combien de joueurs par équipe sont sur le terrain au football ?', array['11', '10', '9', '12'], 0, 'Chaque équipe aligne 11 joueurs, dont le gardien de but.'),
  ('spo-002', 'sport', 1, 'Quelle ville a accueilli les Jeux olympiques d''été 2024 ?', array['Paris', 'Los Angeles', 'Tokyo', 'Londres'], 0, 'Paris a accueilli les JO 2024, un siècle après ceux de 1924. Los Angeles organise ceux de 2028.'),
  ('spo-003', 'sport', 1, 'Sur le Tour de France, quelle est la couleur du maillot du leader du classement général ?', array['Jaune', 'Vert', 'Blanc', 'À pois rouges'], 0, 'Le maillot jaune récompense le leader du classement général. Le vert est pour les points, le blanc pour le meilleur jeune, les pois pour la montagne.'),
  ('act-001', 'actu', 2, 'Quel pays a accueilli les Jeux olympiques d''hiver 2026 ?', array['L''Italie', 'La Suisse', 'La Chine', 'Le Japon'], 0, 'Les JO d''hiver 2026 se sont tenus à Milan et Cortina d''Ampezzo, en Italie.'),
  ('act-002', 'actu', 2, 'Combien de pays ont co-organisé la Coupe du monde de football 2026 ?', array['3', '1', '2', '4'], 0, 'Les États-Unis, le Canada et le Mexique l''ont organisée ensemble, une première à trois pays.'),
  ('act-003', 'actu', 2, 'En quelle année la cathédrale Notre-Dame de Paris a-t-elle rouvert après l''incendie de 2019 ?', array['2024', '2023', '2025', '2022'], 0, 'Notre-Dame a rouvert ses portes en décembre 2024, plus de cinq ans après l''incendie.'),
  ('div-001', 'divers', 1, 'Combien de côtés a un hexagone ?', array['6', '5', '7', '8'], 0, '« Hexa » signifie six en grec. La France est surnommée l''Hexagone pour sa forme.'),
  ('div-002', 'divers', 2, 'Combien de touches compte un piano standard ?', array['88', '76', '92', '64'], 0, 'Un piano standard a 88 touches : 52 blanches et 36 noires.'),
  ('div-003', 'divers', 2, 'Combien d''os compte le squelette d''un adulte humain ?', array['206', '186', '226', '306'], 0, 'Un adulte a 206 os. Un nouveau-né en a davantage, certains fusionnant pendant la croissance.')
on conflict (id) do update
set category = excluded.category,
    difficulty = excluded.difficulty,
    question = excluded.question,
    answers = excluded.answers,
    correct_index = excluded.correct_index,
    explanation = excluded.explanation,
    updated_at = now()
where (questions.category, questions.difficulty, questions.question,
       questions.answers, questions.correct_index, questions.explanation)
  is distinct from
      (excluded.category, excluded.difficulty, excluded.question,
       excluded.answers, excluded.correct_index, excluded.explanation);
