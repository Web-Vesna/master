--
-- Schema Sync 0.9.1 Patch Script
-- Created: Sun, Oct 11, 2015
-- Server Version: 5.1.73
-- Apply To: localhost/apek-energo-test
--

ALTER TABLE `buildings` MODIFY COLUMN `flags` set('editable','new_objects_names_scheme') NOT NULL AFTER `district_id`;
ALTER TABLE `files` ENGINE=InnoDB ROW_FORMAT=Compact row_format=COMPACT;
ALTER TABLE `objects_names` ENGINE=InnoDB ROW_FORMAT=Compact;
ALTER TABLE `objects` ADD COLUMN `object_name_new` int(11) NULL AFTER `objects_subtype`, ADD COLUMN `parent_object` int(11) NULL AFTER `object_name_new`, MODIFY COLUMN `object_name` int(11) NULL AFTER `cost`, ADD INDEX `fk_objects_objects_parent_1_idx` (`parent_object`) USING BTREE, ADD INDEX `fk_objects_objects_names_1_idx` (`object_name_new`) USING BTREE, ADD CONSTRAINT `fk_objects_objects_names_1` FOREIGN KEY `fk_objects_objects_names_1` (`object_name_new`) REFERENCES `objects_names` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION, ADD CONSTRAINT `fk_objects_objects_parent_1` FOREIGN KEY `fk_objects_objects_parent_1` (`parent_object`) REFERENCES `objects` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION;
