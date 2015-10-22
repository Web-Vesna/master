--
-- Schema Sync 0.9.1 Patch Script
-- Created: Sun, Oct 11, 2015
-- Server Version: 5.1.73
-- Apply To: localhost/apek-energo-test
--

ALTER TABLE `buildings` MODIFY COLUMN `flags` set('editable','new_objects_names_scheme','closed') NOT NULL AFTER `district_id`;
ALTER TABLE `files` ENGINE=InnoDB ROW_FORMAT=Compact row_format=COMPACT;
ALTER TABLE `objects_names` ENGINE=InnoDB ROW_FORMAT=Compact;
ALTER TABLE `objects` ADD COLUMN `object_name_new` int(11) NULL AFTER `objects_subtype`, ADD COLUMN `parent_object` int(11) NULL AFTER `object_name_new`, MODIFY COLUMN `object_name` int(11) NULL AFTER `cost`, ADD INDEX `fk_objects_objects_parent_1_idx` (`parent_object`) USING BTREE, ADD INDEX `fk_objects_objects_names_1_idx` (`object_name_new`) USING BTREE, ADD CONSTRAINT `fk_objects_objects_names_1` FOREIGN KEY `fk_objects_objects_names_1` (`object_name_new`) REFERENCES `objects_names` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION, ADD CONSTRAINT `fk_objects_objects_parent_1` FOREIGN KEY `fk_objects_objects_parent_1` (`parent_object`) REFERENCES `objects` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE objects ADD COLUMN characteristic_new VARCHAR(255) AFTER characteristic;
UPDATE objects o JOIN characteristics c ON c.id = o.characteristic SET o.characteristic_new = c.name;
ALTER TABLE objects DROP FOREIGN KEY fk_objects_characteristics1;
ALTER TABLE objects DROP KEY fk_objects_characteristics1_idx;
ALTER TABLE objects DROP COLUMN characteristic;
ALTER TABLE objects CHANGE characteristic_new characteristic VARCHAR(255);
DROP TABLE characteristics;

alter table roles add column text varchar(255) default NULL;
update roles set text = 'Администратор' where id = 1;
update roles set text = 'Менеджер' where id = 3;
update roles set text = 'Пользователь' where id = 4;
