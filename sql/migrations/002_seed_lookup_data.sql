-- ============================================================================
-- Synthetic User Lab - lookup seed data
-- Migration: 002_seed_lookup_data.sql
--
-- Every value is fictional lookup material. Generated email addresses use only
-- RFC 2606 example domains, and phone formats use reserved/fictional ranges.
-- All tables are locale-keyed, so a new locale is primarily a data exercise.
-- ============================================================================

INSERT INTO sul.locales (
    locale_code, display_order, language_code, language_name,
    country_code, country_name, default_phone_prefix,
    full_name_format, street_address_format, address_format,
    middle_name_probability, title_probability,
    postal_code_length, postal_code_regex,
    house_number_min, house_number_max, house_number_suffix_probability
) VALUES
    (
        'en_US', 10, 'en-US', 'English', 'US', 'United States', '+1',
        '{first} {middle} {last}', '{house_number} {street_name}',
        '{street_address}, {city}, {region_code} {postal_code}, {country}',
        0.6500, 0.2800, 5, '^[0-9]{5}$', 1, 9999, 0.0000
    ),
    (
        'de_DE', 20, 'de-DE', 'German', 'DE', 'Germany', '+49',
        '{first} {middle} {last}', '{street_name} {house_number}{house_suffix}',
        '{street_address}, {postal_code} {city}, {country}',
        0.4200, 0.4000, 5, '^[0-9]{5}$', 1, 999, 0.3500
    );

-- ---------------------------------------------------------------------------
-- Regions
-- ---------------------------------------------------------------------------
INSERT INTO sul.regions (locale_code, name, code) VALUES
    ('en_US', 'New York', 'NY'),
    ('en_US', 'California', 'CA'),
    ('en_US', 'Illinois', 'IL'),
    ('en_US', 'Texas', 'TX'),
    ('en_US', 'Arizona', 'AZ'),
    ('en_US', 'Pennsylvania', 'PA'),
    ('en_US', 'Florida', 'FL'),
    ('en_US', 'Ohio', 'OH'),
    ('en_US', 'North Carolina', 'NC'),
    ('en_US', 'Indiana', 'IN'),
    ('en_US', 'Washington', 'WA'),
    ('en_US', 'Colorado', 'CO'),
    ('en_US', 'Massachusetts', 'MA'),
    ('en_US', 'Tennessee', 'TN'),
    ('en_US', 'Oregon', 'OR'),
    ('en_US', 'Georgia', 'GA'),
    ('de_DE', 'Berlin', 'BE'),
    ('de_DE', 'Hamburg', 'HH'),
    ('de_DE', 'Bayern', 'BY'),
    ('de_DE', 'Nordrhein-Westfalen', 'NW'),
    ('de_DE', 'Hessen', 'HE'),
    ('de_DE', 'Baden-Württemberg', 'BW'),
    ('de_DE', 'Sachsen', 'SN'),
    ('de_DE', 'Bremen', 'HB'),
    ('de_DE', 'Niedersachsen', 'NI');

-- ---------------------------------------------------------------------------
-- Cities (weight loosely reflects population; postal_prefix seeds the ZIP/PLZ)
-- ---------------------------------------------------------------------------
INSERT INTO sul.cities (locale_code, region_id, name, postal_prefix, weight)
SELECT v.locale_code, r.id, v.city_name, v.postal_prefix, v.weight
FROM (VALUES
    ('en_US', 'NY', 'New York',      '100', 100),
    ('en_US', 'CA', 'Los Angeles',   '900',  85),
    ('en_US', 'IL', 'Chicago',       '606',  65),
    ('en_US', 'TX', 'Houston',       '770',  60),
    ('en_US', 'AZ', 'Phoenix',       '850',  50),
    ('en_US', 'PA', 'Philadelphia',  '191',  45),
    ('en_US', 'TX', 'San Antonio',   '782',  40),
    ('en_US', 'CA', 'San Diego',     '921',  40),
    ('en_US', 'TX', 'Dallas',        '752',  40),
    ('en_US', 'CA', 'San Jose',      '951',  35),
    ('en_US', 'TX', 'Austin',        '787',  35),
    ('en_US', 'FL', 'Jacksonville',  '322',  30),
    ('en_US', 'OH', 'Columbus',      '432',  30),
    ('en_US', 'NC', 'Charlotte',     '282',  30),
    ('en_US', 'IN', 'Indianapolis',  '462',  28),
    ('en_US', 'WA', 'Seattle',       '981',  28),
    ('en_US', 'CO', 'Denver',        '802',  25),
    ('en_US', 'MA', 'Boston',        '021',  25),
    ('en_US', 'TN', 'Nashville',     '372',  24),
    ('en_US', 'OR', 'Portland',      '972',  22),
    ('en_US', 'GA', 'Atlanta',       '303',  24),
    ('en_US', 'FL', 'Miami',         '331',  24),
    ('de_DE', 'BE', 'Berlin',            '101', 100),
    ('de_DE', 'HH', 'Hamburg',           '200',  65),
    ('de_DE', 'BY', 'München',           '803',  60),
    ('de_DE', 'NW', 'Köln',              '506',  50),
    ('de_DE', 'HE', 'Frankfurt am Main', '603',  45),
    ('de_DE', 'BW', 'Stuttgart',         '701',  40),
    ('de_DE', 'NW', 'Düsseldorf',        '402',  38),
    ('de_DE', 'SN', 'Leipzig',           '041',  35),
    ('de_DE', 'NW', 'Dortmund',          '441',  34),
    ('de_DE', 'NW', 'Essen',             '451',  32),
    ('de_DE', 'HB', 'Bremen',            '281',  30),
    ('de_DE', 'SN', 'Dresden',           '010',  30),
    ('de_DE', 'NI', 'Hannover',          '301',  30),
    ('de_DE', 'BY', 'Nürnberg',          '904',  28),
    ('de_DE', 'NW', 'Duisburg',          '470',  26),
    ('de_DE', 'NW', 'Bochum',            '447',  24),
    ('de_DE', 'NW', 'Wuppertal',         '421',  24),
    ('de_DE', 'NW', 'Bielefeld',         '336',  22),
    ('de_DE', 'NW', 'Bonn',              '531',  22),
    ('de_DE', 'NW', 'Münster',           '481',  22)
) AS v(locale_code, region_code, city_name, postal_prefix, weight)
JOIN sul.regions r
  ON r.locale_code = v.locale_code AND r.code = v.region_code;

-- ---------------------------------------------------------------------------
-- First names (gender-aware)
-- ---------------------------------------------------------------------------
INSERT INTO sul.first_names (locale_code, name, gender) VALUES
    ('en_US', 'James', 'M'), ('en_US', 'Michael', 'M'), ('en_US', 'Robert', 'M'),
    ('en_US', 'John', 'M'), ('en_US', 'David', 'M'), ('en_US', 'William', 'M'),
    ('en_US', 'Richard', 'M'), ('en_US', 'Joseph', 'M'), ('en_US', 'Thomas', 'M'),
    ('en_US', 'Charles', 'M'), ('en_US', 'Christopher', 'M'), ('en_US', 'Daniel', 'M'),
    ('en_US', 'Matthew', 'M'), ('en_US', 'Anthony', 'M'), ('en_US', 'Mark', 'M'),
    ('en_US', 'Donald', 'M'), ('en_US', 'Steven', 'M'), ('en_US', 'Paul', 'M'),
    ('en_US', 'Andrew', 'M'), ('en_US', 'Joshua', 'M'), ('en_US', 'Kenneth', 'M'),
    ('en_US', 'Kevin', 'M'), ('en_US', 'Brian', 'M'), ('en_US', 'George', 'M'),
    ('en_US', 'Timothy', 'M'), ('en_US', 'Ronald', 'M'), ('en_US', 'Edward', 'M'),
    ('en_US', 'Jason', 'M'), ('en_US', 'Jeffrey', 'M'), ('en_US', 'Ryan', 'M'),
    ('en_US', 'Jacob', 'M'), ('en_US', 'Gary', 'M'), ('en_US', 'Nicholas', 'M'),
    ('en_US', 'Eric', 'M'), ('en_US', 'Jonathan', 'M'), ('en_US', 'Stephen', 'M'),
    ('en_US', 'Larry', 'M'), ('en_US', 'Justin', 'M'), ('en_US', 'Scott', 'M'),
    ('en_US', 'Brandon', 'M'), ('en_US', 'Benjamin', 'M'), ('en_US', 'Samuel', 'M'),
    ('en_US', 'Gregory', 'M'), ('en_US', 'Alexander', 'M'), ('en_US', 'Patrick', 'M'),
    ('en_US', 'Frank', 'M'), ('en_US', 'Raymond', 'M'), ('en_US', 'Jack', 'M'),
    ('en_US', 'Dennis', 'M'), ('en_US', 'Jerry', 'M'), ('en_US', 'José', 'M'),
    ('en_US', 'Diego', 'M'), ('en_US', 'Omar', 'M'), ('en_US', 'Kwame', 'M'),
    ('en_US', 'Amir', 'M'), ('en_US', 'Rajesh', 'M'), ('en_US', 'Wei', 'M'),
    ('en_US', 'Carlos', 'M'), ('en_US', 'Mohammed', 'M'), ('en_US', 'Andre', 'M'),
    ('en_US', 'Mary', 'F'), ('en_US', 'Patricia', 'F'), ('en_US', 'Jennifer', 'F'),
    ('en_US', 'Linda', 'F'), ('en_US', 'Elizabeth', 'F'), ('en_US', 'Barbara', 'F'),
    ('en_US', 'Susan', 'F'), ('en_US', 'Jessica', 'F'), ('en_US', 'Sarah', 'F'),
    ('en_US', 'Karen', 'F'), ('en_US', 'Nancy', 'F'), ('en_US', 'Lisa', 'F'),
    ('en_US', 'Betty', 'F'), ('en_US', 'Margaret', 'F'), ('en_US', 'Sandra', 'F'),
    ('en_US', 'Ashley', 'F'), ('en_US', 'Kimberly', 'F'), ('en_US', 'Emily', 'F'),
    ('en_US', 'Donna', 'F'), ('en_US', 'Michelle', 'F'), ('en_US', 'Carol', 'F'),
    ('en_US', 'Amanda', 'F'), ('en_US', 'Dorothy', 'F'), ('en_US', 'Melissa', 'F'),
    ('en_US', 'Deborah', 'F'), ('en_US', 'Stephanie', 'F'), ('en_US', 'Rebecca', 'F'),
    ('en_US', 'Sharon', 'F'), ('en_US', 'Laura', 'F'), ('en_US', 'Cynthia', 'F'),
    ('en_US', 'Kathleen', 'F'), ('en_US', 'Amy', 'F'), ('en_US', 'Angela', 'F'),
    ('en_US', 'Shirley', 'F'), ('en_US', 'Anna', 'F'), ('en_US', 'Brenda', 'F'),
    ('en_US', 'Pamela', 'F'), ('en_US', 'Emma', 'F'), ('en_US', 'Nicole', 'F'),
    ('en_US', 'Helen', 'F'), ('en_US', 'Samantha', 'F'), ('en_US', 'Katherine', 'F'),
    ('en_US', 'Christine', 'F'), ('en_US', 'Debra', 'F'), ('en_US', 'Rachel', 'F'),
    ('en_US', 'Carolyn', 'F'), ('en_US', 'Janet', 'F'), ('en_US', 'Catherine', 'F'),
    ('en_US', 'Maria', 'F'), ('en_US', 'Heather', 'F'), ('en_US', 'Aaliyah', 'F'),
    ('en_US', 'Priya', 'F'), ('en_US', 'Mei', 'F'), ('en_US', 'Sofia', 'F'),
    ('en_US', 'Leila', 'F'), ('en_US', 'Fatima', 'F'), ('en_US', 'Ana', 'F'),
    ('en_US', 'Grace', 'F'), ('en_US', 'Zara', 'F'), ('en_US', 'Jasmine', 'F'),

    ('de_DE', 'Alexander', 'M'), ('de_DE', 'Andreas', 'M'), ('de_DE', 'Bernd', 'M'),
    ('de_DE', 'Christian', 'M'), ('de_DE', 'Daniel', 'M'), ('de_DE', 'David', 'M'),
    ('de_DE', 'Dieter', 'M'), ('de_DE', 'Dirk', 'M'), ('de_DE', 'Felix', 'M'),
    ('de_DE', 'Florian', 'M'), ('de_DE', 'Frank', 'M'), ('de_DE', 'Günter', 'M'),
    ('de_DE', 'Hans', 'M'), ('de_DE', 'Heiko', 'M'), ('de_DE', 'Helmut', 'M'),
    ('de_DE', 'Jan', 'M'), ('de_DE', 'Jens', 'M'), ('de_DE', 'Joachim', 'M'),
    ('de_DE', 'Johannes', 'M'), ('de_DE', 'Jörg', 'M'), ('de_DE', 'Julian', 'M'),
    ('de_DE', 'Jürgen', 'M'), ('de_DE', 'Karl', 'M'), ('de_DE', 'Klaus', 'M'),
    ('de_DE', 'Lars', 'M'), ('de_DE', 'Lukas', 'M'), ('de_DE', 'Manfred', 'M'),
    ('de_DE', 'Marcel', 'M'), ('de_DE', 'Marco', 'M'), ('de_DE', 'Markus', 'M'),
    ('de_DE', 'Martin', 'M'), ('de_DE', 'Matthias', 'M'), ('de_DE', 'Maximilian', 'M'),
    ('de_DE', 'Michael', 'M'), ('de_DE', 'Niklas', 'M'), ('de_DE', 'Norbert', 'M'),
    ('de_DE', 'Oliver', 'M'), ('de_DE', 'Patrick', 'M'), ('de_DE', 'Paul', 'M'),
    ('de_DE', 'Peter', 'M'), ('de_DE', 'Philipp', 'M'), ('de_DE', 'Rainer', 'M'),
    ('de_DE', 'Ralf', 'M'), ('de_DE', 'René', 'M'), ('de_DE', 'Robert', 'M'),
    ('de_DE', 'Rolf', 'M'), ('de_DE', 'Sebastian', 'M'), ('de_DE', 'Stefan', 'M'),
    ('de_DE', 'Thomas', 'M'), ('de_DE', 'Tobias', 'M'), ('de_DE', 'Uwe', 'M'),
    ('de_DE', 'Volker', 'M'), ('de_DE', 'Werner', 'M'), ('de_DE', 'Wolfgang', 'M'),
    ('de_DE', 'Tim', 'M'), ('de_DE', 'Sven', 'M'), ('de_DE', 'Thorsten', 'M'),
    ('de_DE', 'Ulrich', 'M'), ('de_DE', 'Fabian', 'M'), ('de_DE', 'Christoph', 'M'),
    ('de_DE', 'Detlef', 'M'), ('de_DE', 'Egon', 'M'),
    ('de_DE', 'Andrea', 'F'), ('de_DE', 'Angelika', 'F'), ('de_DE', 'Anja', 'F'),
    ('de_DE', 'Anke', 'F'), ('de_DE', 'Anna', 'F'), ('de_DE', 'Annette', 'F'),
    ('de_DE', 'Antje', 'F'), ('de_DE', 'Barbara', 'F'), ('de_DE', 'Birgit', 'F'),
    ('de_DE', 'Brigitte', 'F'), ('de_DE', 'Christina', 'F'), ('de_DE', 'Claudia', 'F'),
    ('de_DE', 'Cornelia', 'F'), ('de_DE', 'Daniela', 'F'), ('de_DE', 'Doris', 'F'),
    ('de_DE', 'Elke', 'F'), ('de_DE', 'Emma', 'F'), ('de_DE', 'Eva', 'F'),
    ('de_DE', 'Franziska', 'F'), ('de_DE', 'Gabriele', 'F'), ('de_DE', 'Gisela', 'F'),
    ('de_DE', 'Heike', 'F'), ('de_DE', 'Helga', 'F'), ('de_DE', 'Ines', 'F'),
    ('de_DE', 'Ingrid', 'F'), ('de_DE', 'Jana', 'F'), ('de_DE', 'Janina', 'F'),
    ('de_DE', 'Johanna', 'F'), ('de_DE', 'Julia', 'F'), ('de_DE', 'Jutta', 'F'),
    ('de_DE', 'Karin', 'F'), ('de_DE', 'Katharina', 'F'), ('de_DE', 'Katrin', 'F'),
    ('de_DE', 'Kerstin', 'F'), ('de_DE', 'Klara', 'F'), ('de_DE', 'Kristin', 'F'),
    ('de_DE', 'Laura', 'F'), ('de_DE', 'Lena', 'F'), ('de_DE', 'Leonie', 'F'),
    ('de_DE', 'Lisa', 'F'), ('de_DE', 'Manuela', 'F'), ('de_DE', 'Maria', 'F'),
    ('de_DE', 'Marion', 'F'), ('de_DE', 'Martina', 'F'), ('de_DE', 'Melanie', 'F'),
    ('de_DE', 'Monika', 'F'), ('de_DE', 'Nadine', 'F'), ('de_DE', 'Nicole', 'F'),
    ('de_DE', 'Petra', 'F'), ('de_DE', 'Renate', 'F'), ('de_DE', 'Sabine', 'F'),
    ('de_DE', 'Sandra', 'F'), ('de_DE', 'Sara', 'F'), ('de_DE', 'Silke', 'F'),
    ('de_DE', 'Simone', 'F'), ('de_DE', 'Sonja', 'F'), ('de_DE', 'Stephanie', 'F'),
    ('de_DE', 'Susanne', 'F'), ('de_DE', 'Tanja', 'F'), ('de_DE', 'Ulrike', 'F'),
    ('de_DE', 'Ursula', 'F'), ('de_DE', 'Ute', 'F'), ('de_DE', 'Vanessa', 'F'),
    ('de_DE', 'Verena', 'F'), ('de_DE', 'Yvonne', 'F'), ('de_DE', 'Charlotte', 'F'),
    ('de_DE', 'Greta', 'F'), ('de_DE', 'Hannah', 'F'), ('de_DE', 'Lea', 'F'),
    ('de_DE', 'Mia', 'F'), ('de_DE', 'Sophie', 'F'), ('de_DE', 'Emilia', 'F'),
    ('de_DE', 'Marie', 'F'), ('de_DE', 'Luisa', 'F');

-- Gentle frequency shaping: common names are selected more often.
UPDATE sul.first_names
SET weight = 100
WHERE locale_code = 'en_US'
  AND name IN ('James', 'Michael', 'Robert', 'John', 'David', 'Mary', 'Jennifer', 'Linda', 'Elizabeth', 'Patricia');
UPDATE sul.first_names
SET weight = 70
WHERE locale_code = 'de_DE'
  AND name IN ('Alexander', 'Andreas', 'Christian', 'Daniel', 'Michael', 'Anna', 'Julia', 'Katharina', 'Sabine', 'Petra');

-- ---------------------------------------------------------------------------
-- Middle names
-- ---------------------------------------------------------------------------
INSERT INTO sul.middle_names (locale_code, name) VALUES
    ('en_US', 'Lee'), ('en_US', 'James'), ('en_US', 'Marie'), ('en_US', 'Ann'),
    ('en_US', 'Rose'), ('en_US', 'John'), ('en_US', 'Michael'), ('en_US', 'Elizabeth'),
    ('en_US', 'Lynn'), ('en_US', 'Ray'), ('en_US', 'Grace'), ('en_US', 'Thomas'),
    ('en_US', 'Jane'), ('en_US', 'Paul'), ('en_US', 'Louise'), ('en_US', 'Scott'),
    ('en_US', 'Jean'), ('en_US', 'Allen'), ('en_US', 'Mae'), ('en_US', 'William'),
    ('en_US', 'Kay'), ('en_US', 'David'), ('en_US', 'Ruth'), ('en_US', 'Dean'),
    ('en_US', 'Faye'), ('en_US', 'Jo'), ('en_US', 'Robert'), ('en_US', 'Claire'),
    ('en_US', 'Nicole'), ('en_US', 'Blake'), ('en_US', 'Quinn'), ('en_US', 'Avery'),
    ('en_US', 'Taylor'), ('en_US', 'Morgan'), ('en_US', 'Riley'), ('en_US', 'Jordan'),
    ('en_US', 'Casey'), ('en_US', 'Cameron'), ('en_US', 'Dakota'), ('en_US', 'Emerson'),
    ('en_US', 'Finley'), ('en_US', 'Hayden'), ('en_US', 'Jamie'), ('en_US', 'Kendall'),
    ('en_US', 'Parker'), ('en_US', 'Peyton'), ('en_US', 'Reese'), ('en_US', 'Rowan'),
    ('en_US', 'Sage'), ('en_US', 'Skyler'),
    ('de_DE', 'Maria'), ('de_DE', 'Johann'), ('de_DE', 'Josef'), ('de_DE', 'Anna'),
    ('de_DE', 'Elisabeth'), ('de_DE', 'Friedrich'), ('de_DE', 'Wilhelm'), ('de_DE', 'Charlotte'),
    ('de_DE', 'Louise'), ('de_DE', 'Sophie'), ('de_DE', 'Marie'), ('de_DE', 'Luise'),
    ('de_DE', 'Heinrich'), ('de_DE', 'Karl'), ('de_DE', 'Anton'), ('de_DE', 'Franz'),
    ('de_DE', 'Josefine'), ('de_DE', 'Johanna'), ('de_DE', 'Katharina'), ('de_DE', 'Margarete'),
    ('de_DE', 'Therese'), ('de_DE', 'August'), ('de_DE', 'Gustav'), ('de_DE', 'Otto'),
    ('de_DE', 'Paul'), ('de_DE', 'Peter'), ('de_DE', 'Helene'), ('de_DE', 'Irene'),
    ('de_DE', 'Klara'), ('de_DE', 'Rosa'), ('de_DE', 'Ernst'), ('de_DE', 'Hermann'),
    ('de_DE', 'Rudolf'), ('de_DE', 'Walter'), ('de_DE', 'Albrecht'), ('de_DE', 'Berta'),
    ('de_DE', 'Frieda'), ('de_DE', 'Hedwig'), ('de_DE', 'Ida'), ('de_DE', 'Lotte'),
    ('de_DE', 'Mathilde'), ('de_DE', 'Pauline'), ('de_DE', 'Wilhelmine'), ('de_DE', 'Albert'),
    ('de_DE', 'Eduard'), ('de_DE', 'Konrad'), ('de_DE', 'Lorenz'), ('de_DE', 'Max'),
    ('de_DE', 'Moritz'), ('de_DE', 'Theodor');

-- ---------------------------------------------------------------------------
-- Last names
-- ---------------------------------------------------------------------------
INSERT INTO sul.last_names (locale_code, name) VALUES
    ('en_US', 'Smith'), ('en_US', 'Johnson'), ('en_US', 'Williams'), ('en_US', 'Brown'),
    ('en_US', 'Jones'), ('en_US', 'Garcia'), ('en_US', 'Miller'), ('en_US', 'Davis'),
    ('en_US', 'Rodriguez'), ('en_US', 'Martinez'), ('en_US', 'Hernandez'), ('en_US', 'Lopez'),
    ('en_US', 'Gonzalez'), ('en_US', 'Wilson'), ('en_US', 'Anderson'), ('en_US', 'Thomas'),
    ('en_US', 'Taylor'), ('en_US', 'Moore'), ('en_US', 'Jackson'), ('en_US', 'Martin'),
    ('en_US', 'Lee'), ('en_US', 'Perez'), ('en_US', 'Thompson'), ('en_US', 'White'),
    ('en_US', 'Harris'), ('en_US', 'Sanchez'), ('en_US', 'Clark'), ('en_US', 'Ramirez'),
    ('en_US', 'Lewis'), ('en_US', 'Robinson'), ('en_US', 'Walker'), ('en_US', 'Young'),
    ('en_US', 'Allen'), ('en_US', 'King'), ('en_US', 'Wright'), ('en_US', 'Scott'),
    ('en_US', 'Torres'), ('en_US', 'Nguyen'), ('en_US', 'Hill'), ('en_US', 'Flores'),
    ('en_US', 'Green'), ('en_US', 'Adams'), ('en_US', 'Nelson'), ('en_US', 'Baker'),
    ('en_US', 'Hall'), ('en_US', 'Rivera'), ('en_US', 'Campbell'), ('en_US', 'Mitchell'),
    ('en_US', 'Carter'), ('en_US', 'Roberts'), ('en_US', 'Gomez'), ('en_US', 'Phillips'),
    ('en_US', 'Evans'), ('en_US', 'Turner'), ('en_US', 'Diaz'), ('en_US', 'Parker'),
    ('en_US', 'Cruz'), ('en_US', 'Edwards'), ('en_US', 'Collins'), ('en_US', 'Reyes'),
    ('en_US', 'Stewart'), ('en_US', 'Morris'), ('en_US', 'Morales'), ('en_US', 'Murphy'),
    ('en_US', 'Cook'), ('en_US', 'Rogers'), ('en_US', 'Gutierrez'), ('en_US', 'Ortiz'),
    ('en_US', 'Morgan'), ('en_US', 'Cooper'), ('en_US', 'Peterson'), ('en_US', 'Bailey'),
    ('en_US', 'Reed'), ('en_US', 'Kelly'), ('en_US', 'Howard'), ('en_US', 'Ramos'),
    ('en_US', 'Kim'), ('en_US', 'Cox'), ('en_US', 'Ward'), ('en_US', 'Richardson'),
    ('en_US', 'Watson'), ('en_US', 'Brooks'), ('en_US', 'Chavez'), ('en_US', 'Wood'),
    ('en_US', 'James'), ('en_US', 'Bennett'), ('en_US', 'Gray'), ('en_US', 'Mendoza'),
    ('en_US', 'Ruiz'), ('en_US', 'Hughes'), ('en_US', 'Price'), ('en_US', 'Alvarez'),
    ('en_US', 'Castillo'), ('en_US', 'Sanders'), ('en_US', 'Patel'), ('en_US', 'Myers'),
    ('en_US', 'Long'), ('en_US', 'Ross'), ('en_US', 'Foster'), ('en_US', 'Jimenez'),
    ('en_US', 'Powell'), ('en_US', 'Jenkins'),
    ('de_DE', 'Müller'), ('de_DE', 'Schmidt'), ('de_DE', 'Schneider'), ('de_DE', 'Fischer'),
    ('de_DE', 'Weber'), ('de_DE', 'Meyer'), ('de_DE', 'Wagner'), ('de_DE', 'Becker'),
    ('de_DE', 'Schulz'), ('de_DE', 'Hoffmann'), ('de_DE', 'Schäfer'), ('de_DE', 'Koch'),
    ('de_DE', 'Bauer'), ('de_DE', 'Richter'), ('de_DE', 'Klein'), ('de_DE', 'Wolf'),
    ('de_DE', 'Schröder'), ('de_DE', 'Neumann'), ('de_DE', 'Schwarz'), ('de_DE', 'Zimmermann'),
    ('de_DE', 'Braun'), ('de_DE', 'Krüger'), ('de_DE', 'Hofmann'), ('de_DE', 'Hartmann'),
    ('de_DE', 'Lange'), ('de_DE', 'Schmitt'), ('de_DE', 'Werner'), ('de_DE', 'Schmitz'),
    ('de_DE', 'Krause'), ('de_DE', 'Meier'), ('de_DE', 'Lehmann'), ('de_DE', 'Schmid'),
    ('de_DE', 'Schulze'), ('de_DE', 'Maier'), ('de_DE', 'Köhler'), ('de_DE', 'Herrmann'),
    ('de_DE', 'König'), ('de_DE', 'Walter'), ('de_DE', 'Mayer'), ('de_DE', 'Huber'),
    ('de_DE', 'Kaiser'), ('de_DE', 'Fuchs'), ('de_DE', 'Peters'), ('de_DE', 'Lang'),
    ('de_DE', 'Scholz'), ('de_DE', 'Möller'), ('de_DE', 'Weiß'), ('de_DE', 'Jung'),
    ('de_DE', 'Hahn'), ('de_DE', 'Schubert'), ('de_DE', 'Vogel'), ('de_DE', 'Friedrich'),
    ('de_DE', 'Keller'), ('de_DE', 'Günther'), ('de_DE', 'Frank'), ('de_DE', 'Berger'),
    ('de_DE', 'Winkler'), ('de_DE', 'Roth'), ('de_DE', 'Beck'), ('de_DE', 'Lorenz'),
    ('de_DE', 'Baumann'), ('de_DE', 'Franke'), ('de_DE', 'Albrecht'), ('de_DE', 'Schuster'),
    ('de_DE', 'Simon'), ('de_DE', 'Ludwig'), ('de_DE', 'Böhm'), ('de_DE', 'Winter'),
    ('de_DE', 'Kraus'), ('de_DE', 'Martin'), ('de_DE', 'Schumacher'), ('de_DE', 'Krämer'),
    ('de_DE', 'Vogt'), ('de_DE', 'Stein'), ('de_DE', 'Jäger'), ('de_DE', 'Otto'),
    ('de_DE', 'Sommer'), ('de_DE', 'Groß'), ('de_DE', 'Seidel'), ('de_DE', 'Heinrich'),
    ('de_DE', 'Brandt'), ('de_DE', 'Haas'), ('de_DE', 'Schreiber'), ('de_DE', 'Graf'),
    ('de_DE', 'Schulte'), ('de_DE', 'Dietrich'), ('de_DE', 'Ziegler'), ('de_DE', 'Kuhn'),
    ('de_DE', 'Kühn'), ('de_DE', 'Pohl'), ('de_DE', 'Engel'), ('de_DE', 'Horn'),
    ('de_DE', 'Busch'), ('de_DE', 'Bergmann'), ('de_DE', 'Thomas'), ('de_DE', 'Voigt'),
    ('de_DE', 'Sauer'), ('de_DE', 'Arnold'), ('de_DE', 'Wolff'), ('de_DE', 'Pfeiffer');

UPDATE sul.last_names SET weight = 100
WHERE locale_code = 'en_US' AND name IN ('Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis');
UPDATE sul.last_names SET weight = 100
WHERE locale_code = 'de_DE' AND name IN ('Müller', 'Schmidt', 'Schneider', 'Fischer', 'Weber', 'Meyer', 'Wagner', 'Becker');

-- ---------------------------------------------------------------------------
-- Titles
-- ---------------------------------------------------------------------------
INSERT INTO sul.titles (locale_code, title, gender, weight) VALUES
    ('en_US', 'Mr.',  'M',    100),
    ('en_US', 'Ms.',  'F',    100),
    ('en_US', 'Mrs.', 'F',     35),
    ('en_US', 'Dr.',  NULL,    18),
    ('en_US', 'Prof.', NULL,    7),
    ('en_US', 'Mx.',  NULL,     5),
    ('de_DE', 'Herr', 'M',    100),
    ('de_DE', 'Frau', 'F',    100),
    ('de_DE', 'Dr.',  NULL,    25),
    ('de_DE', 'Prof.', NULL,   10),
    ('de_DE', 'Prof. Dr.', NULL, 8);

-- ---------------------------------------------------------------------------
-- Streets
-- ---------------------------------------------------------------------------
INSERT INTO sul.street_names (locale_code, name) VALUES
    ('en_US', 'Main Street'), ('en_US', 'Oak Street'), ('en_US', 'Pine Street'),
    ('en_US', 'Maple Avenue'), ('en_US', 'Cedar Lane'), ('en_US', 'Elm Street'),
    ('en_US', 'Washington Avenue'), ('en_US', 'Lake Drive'), ('en_US', 'Hill Road'),
    ('en_US', 'Park Avenue'), ('en_US', 'Walnut Street'), ('en_US', 'Spring Street'),
    ('en_US', 'North Avenue'), ('en_US', 'Ridge Road'), ('en_US', 'Church Street'),
    ('en_US', 'Willow Lane'), ('en_US', 'Sunset Boulevard'), ('en_US', 'Highland Avenue'),
    ('en_US', 'Forest Drive'), ('en_US', 'River Road'), ('en_US', 'Meadow Lane'),
    ('en_US', 'Adams Street'), ('en_US', 'Jefferson Avenue'), ('en_US', 'Lincoln Street'),
    ('en_US', 'Jackson Avenue'), ('en_US', 'Madison Street'), ('en_US', 'Franklin Street'),
    ('en_US', 'Chestnut Street'), ('en_US', 'Spruce Street'), ('en_US', 'Birch Lane'),
    ('en_US', 'Willow Way'), ('en_US', 'Orchard Road'), ('en_US', 'Cherry Street'),
    ('en_US', 'Magnolia Drive'), ('en_US', 'Dogwood Lane'), ('en_US', 'Sycamore Street'),
    ('en_US', 'Aspen Court'), ('en_US', 'Juniper Lane'), ('en_US', 'Cambridge Drive'),
    ('en_US', 'Berkshire Road'), ('en_US', 'Fairview Avenue'), ('en_US', 'Prospect Street'),
    ('en_US', 'Union Street'), ('en_US', 'Market Street'), ('en_US', 'Water Street'),
    ('en_US', 'School Street'), ('en_US', 'Mill Road'), ('en_US', 'Bridge Street'),
    ('en_US', 'Center Street'), ('en_US', 'Prospect Avenue'), ('en_US', 'Colonial Drive'),
    ('en_US', 'Crescent Street'), ('en_US', 'Valley Road'), ('en_US', 'Summit Avenue'),
    ('en_US', 'Lakeview Drive'), ('en_US', 'Hillcrest Road'), ('en_US', 'Riverside Drive'),
    ('en_US', 'Woodland Avenue'), ('en_US', 'Meadowbrook Lane'), ('en_US', 'Green Street'),
    ('en_US', 'Broad Street'), ('en_US', 'Pearl Street'), ('en_US', 'Court Street'),
    ('en_US', 'State Street'), ('en_US', 'Grove Street'), ('en_US', 'Ridge Avenue'),
    ('en_US', 'East Street'), ('en_US', 'West Street'), ('en_US', 'South Street'),
    ('en_US', 'Taylor Street'), ('en_US', 'Grant Avenue'), ('en_US', 'Wilson Street'),
    ('en_US', 'Roosevelt Avenue'), ('en_US', 'Kennedy Drive'), ('en_US', 'Liberty Street'),
    ('en_US', 'Columbia Avenue'), ('en_US', 'University Drive'), ('en_US', 'College Street'),
    ('en_US', 'Academy Road'), ('en_US', 'Harbor Drive'), ('en_US', 'Beach Road'),
    ('en_US', 'Bay Street'), ('en_US', 'Ocean Avenue'), ('en_US', 'Canyon Road'),
    ('en_US', 'Desert Drive'), ('en_US', 'Prairie Lane'), ('en_US', 'Ridgeview Court'),
    ('en_US', 'Stonebridge Road'), ('en_US', 'Heather Lane'), ('en_US', 'Fox Run Drive'),
    ('en_US', 'Deer Path'), ('en_US', 'Creekside Drive'), ('en_US', 'Brookside Avenue'),
    ('en_US', 'Cobblestone Lane'), ('en_US', 'Winchester Drive'), ('en_US', 'Bristol Road'),
    ('en_US', 'Devon Lane'), ('en_US', 'Hampton Court'), ('en_US', 'Kingsley Road'),
    ('en_US', 'Pembrook Drive'), ('en_US', 'Ashford Lane'), ('en_US', 'Windsor Drive'),
    ('en_US', 'Camden Road'), ('en_US', 'Kensington Way'), ('en_US', 'Chelsea Lane'),
    ('en_US', 'Dover Street'), ('en_US', 'Oxford Court'), ('en_US', 'Regent Street'),
    ('en_US', 'Somerset Drive'), ('en_US', 'Wexford Road'), ('en_US', 'Brentwood Avenue'),
    ('en_US', 'Claremont Street'), ('en_US', 'Eastwood Drive'), ('en_US', 'Glenview Road'),
    ('en_US', 'Hawthorne Lane'), ('en_US', 'Ivy Court'), ('en_US', 'Jasmine Way'),
    ('en_US', 'Larkspur Lane'), ('en_US', 'Nightingale Road'), ('en_US', 'Quail Run'),
    ('en_US', 'Saddleback Drive'), ('en_US', 'Thistle Lane'), ('en_US', 'Vine Street'),
    ('en_US', 'Wildflower Drive'), ('en_US', 'Yarrow Court'), ('en_US', 'Zinnia Lane'),
    ('de_DE', 'Hauptstraße'), ('de_DE', 'Schulstraße'), ('de_DE', 'Gartenstraße'),
    ('de_DE', 'Dorfstraße'), ('de_DE', 'Bahnhofstraße'), ('de_DE', 'Kirchstraße'),
    ('de_DE', 'Lindenstraße'), ('de_DE', 'Bergstraße'), ('de_DE', 'Ringstraße'),
    ('de_DE', 'Mozartstraße'), ('de_DE', 'Schillerstraße'), ('de_DE', 'Goethestraße'),
    ('de_DE', 'Beethovenstraße'), ('de_DE', 'Lessingstraße'), ('de_DE', 'Friedrichstraße'),
    ('de_DE', 'Wilhelmstraße'), ('de_DE', 'Kaiserstraße'), ('de_DE', 'Königstraße'),
    ('de_DE', 'Marienstraße'), ('de_DE', 'Rosenstraße'), ('de_DE', 'Birkenweg'),
    ('de_DE', 'Amselweg'), ('de_DE', 'Buchenweg'), ('de_DE', 'Eichenweg'),
    ('de_DE', 'Erlenweg'), ('de_DE', 'Fichtenweg'), ('de_DE', 'Ahornweg'),
    ('de_DE', 'Tannenweg'), ('de_DE', 'Wiesenweg'), ('de_DE', 'Feldweg'),
    ('de_DE', 'Waldweg'), ('de_DE', 'Bergweg'), ('de_DE', 'Kirchweg'),
    ('de_DE', 'Mühlenweg'), ('de_DE', 'Schulweg'), ('de_DE', 'Gartenweg'),
    ('de_DE', 'Panoramaweg'), ('de_DE', 'Sonnenweg'), ('de_DE', 'Blumenweg'),
    ('de_DE', 'Am Anger'), ('de_DE', 'Am Bahnhof'), ('de_DE', 'Am Markt'),
    ('de_DE', 'Am Park'), ('de_DE', 'Am Stadtpark'), ('de_DE', 'An der Kirche'),
    ('de_DE', 'Auf dem Hügel'), ('de_DE', 'Im Winkel'), ('de_DE', 'In den Gärten'),
    ('de_DE', 'Zum Sportplatz'), ('de_DE', 'Zur Mühle'), ('de_DE', 'Hafenstraße'),
    ('de_DE', 'Uferstraße'), ('de_DE', 'Marktstraße'), ('de_DE', 'Mühlenstraße'),
    ('de_DE', 'Poststraße'), ('de_DE', 'Rathausstraße'), ('de_DE', 'Ringweg'),
    ('de_DE', 'Sandstraße'), ('de_DE', 'Schlossstraße'), ('de_DE', 'Seestraße'),
    ('de_DE', 'Steinweg'), ('de_DE', 'Talstraße'), ('de_DE', 'Turmstraße'),
    ('de_DE', 'Waldstraße'), ('de_DE', 'Wasserstraße'), ('de_DE', 'Weidenweg'),
    ('de_DE', 'Zeppelinstraße'), ('de_DE', 'Pestalozzistraße'), ('de_DE', 'Heinrich-Heine-Straße'),
    ('de_DE', 'Karl-Marx-Straße'), ('de_DE', 'Clara-Zetkin-Straße'), ('de_DE', 'Rosa-Luxemburg-Straße'),
    ('de_DE', 'Breite Straße'), ('de_DE', 'Lange Straße'), ('de_DE', 'Kurze Straße'),
    ('de_DE', 'Neue Straße'), ('de_DE', 'Alte Straße'), ('de_DE', 'Große Straße'),
    ('de_DE', 'Kleine Straße'), ('de_DE', 'Mittelstraße'), ('de_DE', 'Obere Straße'),
    ('de_DE', 'Untere Straße'), ('de_DE', 'Vordere Straße'), ('de_DE', 'Hintere Straße'),
    ('de_DE', 'Zur Alten Mühle'), ('de_DE', 'Am Waldrand'), ('de_DE', 'Am Wiesengrund'),
    ('de_DE', 'Birkenallee'), ('de_DE', 'Kastanienallee'), ('de_DE', 'Eichenallee'),
    ('de_DE', 'Lindenallee'), ('de_DE', 'Akazienweg'), ('de_DE', 'Fliederweg'),
    ('de_DE', 'Holunderweg'), ('de_DE', 'Jasminweg'), ('de_DE', 'Lavendelweg'),
    ('de_DE', 'Nelkenweg'), ('de_DE', 'Rosenweg'), ('de_DE', 'Tulpenweg'),
    ('de_DE', 'Veilchenweg'), ('de_DE', 'Irisweg'), ('de_DE', 'Buchenallee'),
    ('de_DE', 'Erlenallee'), ('de_DE', 'Fichtenallee'), ('de_DE', 'Tannenallee'),
    ('de_DE', 'Wiesenallee'), ('de_DE', 'Feldallee'), ('de_DE', 'Bergallee'),
    ('de_DE', 'Schlossallee'), ('de_DE', 'Parkallee'), ('de_DE', 'Uferallee'),
    ('de_DE', 'Sonnenallee'), ('de_DE', 'Gartenallee'), ('de_DE', 'Schulallee');

-- ---------------------------------------------------------------------------
-- Email domains (shared, RFC 2606 example domains) and local-part patterns
-- ---------------------------------------------------------------------------
INSERT INTO sul.email_domains (locale_code, domain, weight) VALUES
    (NULL, 'example.com', 60),
    (NULL, 'example.net', 25),
    (NULL, 'example.org', 15);

INSERT INTO sul.email_patterns (locale_code, pattern, weight) VALUES
    ('en_US', '{first}.{last}', 60),
    ('en_US', '{first}{last}', 20),
    ('en_US', '{fi}{last}', 12),
    ('en_US', '{first}_{last}', 5),
    ('en_US', '{first}.{fi}{last}', 3),
    ('de_DE', '{first}.{last}', 55),
    ('de_DE', '{first}{last}', 20),
    ('de_DE', '{fi}{last}', 15),
    ('de_DE', '{first}_{last}', 5),
    ('de_DE', '{first}.{fi}{last}', 5);

-- ---------------------------------------------------------------------------
-- Phone formats. US uses the NANP 555-0100..0199 fictional range. German
-- patterns use the (030) 23125... range reserved for fictional use.
-- ---------------------------------------------------------------------------
INSERT INTO sul.phone_formats (locale_code, format_pattern, weight) VALUES
    ('en_US', '(###) 555-01##', 55),
    ('en_US', '###-555-01##', 30),
    ('en_US', '+1 ###-555-01##', 15),
    ('de_DE', '030 23125###', 55),
    ('de_DE', '(030) 23125###', 30),
    ('de_DE', '+49 30 23125###', 15);

-- ---------------------------------------------------------------------------
-- Localised physical attributes
-- ---------------------------------------------------------------------------
INSERT INTO sul.eye_colors (locale_code, color_name, weight) VALUES
    ('en_US', 'Brown', 45), ('en_US', 'Blue', 30), ('en_US', 'Green', 15),
    ('en_US', 'Hazel', 8), ('en_US', 'Gray', 2),
    ('de_DE', 'Braun', 45), ('de_DE', 'Blau', 30), ('de_DE', 'Grün', 15),
    ('de_DE', 'Haselnuss', 8), ('de_DE', 'Grau', 2);

INSERT INTO sul.hair_colors (locale_code, color_name, weight) VALUES
    ('en_US', 'Black', 30), ('en_US', 'Brown', 40), ('en_US', 'Blonde', 20),
    ('en_US', 'Auburn', 4), ('en_US', 'Red', 3), ('en_US', 'Gray', 3),
    ('de_DE', 'Schwarz', 30), ('de_DE', 'Braun', 40), ('de_DE', 'Blond', 20),
    ('de_DE', 'Rot', 4), ('de_DE', 'Dunkelrot', 3), ('de_DE', 'Grau', 3);

-- ---------------------------------------------------------------------------
-- Body distributions in centimetres and kilograms
-- ---------------------------------------------------------------------------
INSERT INTO sul.body_statistics (
    locale_code, gender,
    height_mean_cm, height_sd_cm, height_min_cm, height_max_cm,
    weight_mean_kg, weight_sd_kg, weight_min_kg, weight_max_kg
) VALUES
    ('en_US', 'M', 177.0, 7.5, 145.0, 212.0,  86.0, 13.0,  48.0, 190.0),
    ('en_US', 'F', 163.0, 7.0, 138.0, 202.0,  74.0, 12.5,  42.0, 175.0),
    ('de_DE', 'M', 180.0, 7.5, 148.0, 214.0,  85.0, 12.0,  48.0, 190.0),
    ('de_DE', 'F', 166.0, 6.5, 140.0, 204.0,  68.0, 11.0,  42.0, 170.0);
