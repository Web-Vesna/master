-- MySQL Workbench Synchronization
-- Generated: 2015-04-07 03:48
-- Model: New Model
-- Version: 1.0
-- Project: Name of the project
-- Author: Pavel Berezhnoy

SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='TRADITIONAL,ALLOW_INVALID_DATES';

CREATE SCHEMA IF NOT EXISTS `apek-energo` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ;

CREATE TABLE IF NOT EXISTS `apek-energo`.`users` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `role` INT(11) NOT NULL,
  `login` VARCHAR(45) NOT NULL,
  `pass` VARCHAR(45) NOT NULL,
  `name` VARCHAR(45) NULL DEFAULT NULL,
  `lastname` VARCHAR(45) NULL DEFAULT NULL,
  `email` VARCHAR(45) NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  INDEX `fk_users_roles_idx` (`role` ASC),
  UNIQUE INDEX `login_UNIQUE` (`login` ASC),
  CONSTRAINT `fk_users_roles`
    FOREIGN KEY (`role`)
    REFERENCES `apek-energo`.`roles` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`roles` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(45) NULL DEFAULT NULL,
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`districts` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(512) NOT NULL,
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`companies` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `district_id` INT(11) NOT NULL,
  `name` VARCHAR(512) NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `fk_companies_districts1_idx` (`district_id` ASC),
  CONSTRAINT `fk_companies_districts1`
    FOREIGN KEY (`district_id`)
    REFERENCES `apek-energo`.`districts` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`buildings` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `contract_id` INT(11) NOT NULL DEFAULT 0,
  `company_id` INT(11) NOT NULL,
  `status` VARCHAR(64) NOT NULL DEFAULT '',
  `name` VARCHAR(512) NOT NULL DEFAULT '',
  `corpus` VARCHAR(512) NOT NULL DEFAULT '',
  `cost` INT(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  INDEX `fk_buildings_companies1_idx` (`company_id` ASC),
  CONSTRAINT `fk_buildings_companies1`
    FOREIGN KEY (`company_id`)
    REFERENCES `apek-energo`.`companies` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`categories` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(256) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`objects` (
  `characteristic` VARCHAR(512) NOT NULL DEFAULT '',
  `length` INT(11) NOT NULL DEFAULT 0,
  `size` INT(11) NOT NULL DEFAULT 0,
  `isolation` INT(11) NOT NULL,
  `laying_method` INT(11) NOT NULL,
  `install_year` INT(11) NOT NULL DEFAULT 2000,
  `reconstruction_year` INT(11) NOT NULL DEFAULT 2000,
  `cost` INT(11) NOT NULL DEFAULT 0,
  `category` INT(11) NOT NULL,
  `building` INT(11) NOT NULL,
  `normal_usage_limit` INT(11) NOT NULL DEFAULT 0,
  `usage_limit` INT(11) NOT NULL DEFAULT 0,
  `amortisation_per_year` FLOAT(11) NOT NULL DEFAULT 0.0,
  `amortisation` FLOAT(11) NOT NULL DEFAULT 0.0,
  INDEX `fk_objects_isolations1_idx` (`isolation` ASC),
  INDEX `fk_objects_laying_methods1_idx` (`laying_method` ASC),
  INDEX `fk_objects_categories1_idx` (`category` ASC),
  INDEX `fk_objects_buildings1_idx` (`building` ASC),
  CONSTRAINT `fk_objects_isolations1`
    FOREIGN KEY (`isolation`)
    REFERENCES `apek-energo`.`isolations` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_objects_laying_methods1`
    FOREIGN KEY (`laying_method`)
    REFERENCES `apek-energo`.`laying_methods` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_objects_categories1`
    FOREIGN KEY (`category`)
    REFERENCES `apek-energo`.`categories` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_objects_buildings1`
    FOREIGN KEY (`building`)
    REFERENCES `apek-energo`.`buildings` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`isolations` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(256) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`laying_methods` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(256) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;


SET SQL_MODE=@OLD_SQL_MODE;
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
