SET foreign_key_checks = 0;

DROP TABLE IF EXISTS A;
DROP TABLE IF EXISTS B;

CREATE TEMPORARY TABLE A(id INT(11), name VARCHAR(512));
CREATE TEMPORARY TABLE B(id INT(11), main_id INT(11));

INSERT INTO A(id, name) SELECT MIN(id), name FROM companies GROUP BY name;
INSERT INTO B(id, main_id) SELECT c.id, aa.id FROM companies c JOIN A aa ON aa.name = c.name AND aa.id != c.id;

ALTER TABLE buildings ADD COLUMN district_id int(11) NOT NULL;

ALTER TABLE buildings ADD constraint `fk_buildings_districts1` FOREIGN KEY (`district_id`)
    REFERENCES `districts` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION;

UPDATE buildings b JOIN companies c ON c.id = company_id SET b.district_id = c.district_id;
UPDATE buildings buil JOIN B bb ON bb.id = buil.company_id SET buil.company_id = bb.main_id;

ALTER TABLE companies DROP KEY fk_companies_districts1_idx, DROP COLUMN district_id, DROP FOREIGN KEY fk_companies_districts1;
DELETE FROM companies WHERE id IN (SELECT id FROM B);

ALTER TABLE buildings ADD COLUMN flags SET('editable') NOT NULL;

SET foreign_key_checks = 1;
