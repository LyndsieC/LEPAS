#####
# Code for pulling data for FTG
# Originally DRO (11 Feb 20), updated JMH 2 Feb 21

###
# Required libraries
###
library(tidyverse)
library(RSQLite)
library(here)

####
# Get data from database
####

# location of database
# database should be kept outside of repo
# I keep right outside of my github repo, find with getwd
# put in name of db
LEPASdbPath <- file.path(here::here("/Users/hood.211/Dropbox/JMH_dropbox/stephanson2/projects/6_Research/FADX09/01_LEPASgitHub/"), 
                         "LEPAS_20210201.db")

# Connect to database -- change filepath as needed.
lpdb <- dbConnect(SQLite(), LEPASdbPath)

# Pull relevant columns from tables using embedded SQL code.
zfin <- dbGetQuery(lpdb, "SELECT 
                   ZF.Sample_ID,
                   ZS.Sample_date,
                   ZS.Sample_site,
                   ZF.Genus_sp_lifestage,
                   ZF.Life_stage,
                   ZF.Number_counted,
                   ZF.Zoop_density,
                   ZF.Zoop_biomass,
                   ZF.Zoop_len_avg,
                   ZT.Order1,
                   ZS.Project
                   FROM Zoop_final ZF
                   LEFT JOIN Zoop_sample_info ZS ON ZF.Sample_ID = ZS.Sample_ID
                   LEFT JOIN Zoop_taxa_groups ZT ON ZF.Genus_sp_lifestage = ZT.Genus_sp_lifestage
                   WHERE Sample_date LIKE '%2020%' AND Project='LEPAS'")



############
# PROCESS AND SUMMARIZE DATA
############

############
# 1) aggregate across younger/older ( Genus_sp_lifestage and lifestage2 (w/o younger older))
############

FTG1 <- zfin %>% 
  # turn NAs in density into zeros
  mutate(Zoop_density = ifelse(is.na(Zoop_density), 0, Zoop_density)) %>% 
  # make all younger individuals immatures - year-to-year comparisons are not possible without this
  # Limnocalanus is the only copepod this doesn't apply too
  mutate(Genus_sp_lifestage = ifelse(Order1=="Calanoida" & Life_stage=="Younger", "Calanoida_immature", Genus_sp_lifestage),
         Genus_sp_lifestage = ifelse(Order1=="Cyclopoida" & Life_stage=="Younger", "Cyclopidae_immature", Genus_sp_lifestage)) %>% 
  # make new lifestage with younger/older combined and Egg
  mutate(Life_stage2 = as.factor(ifelse(Life_stage == "Egg", Life_stage,
                                        ifelse(Life_stage == "Older", "YO",
                                               ifelse(Life_stage == "Younger", "YO", Life_stage))))) %>% 
  # THIS CORRECTS AN ERROR IN THE 2020 UPLOAD
  mutate(Genus_sp_lifestage = ifelse(Genus_sp_lifestage == "Ploesoma_sp", "Ploesoma_sp.",Genus_sp_lifestage)) %>% 
  mutate(across(c(Sample_ID, Sample_site,  Genus_sp_lifestage, Life_stage), factor)) %>% 
  # drop columns
  select( -Project, -Order1) %>%
  # select FTG sites
  filter(Sample_site %in% c("1279_20m", "1281_10m", "27-918", "37-890")) %>% 
  # true grouping variables are smp_id, and GSL
  # but we wat to keep smp_date and smp_site
  group_by(Sample_ID,  Genus_sp_lifestage, Sample_date, Sample_site, Life_stage2) %>%
  #dups were generated by using mutate here, not summarize
  summarize(Number_counted = sum(Number_counted, na.rm=T),
            Zoop_density = sum(Zoop_density, na.rm=T),
            Zoop_biomass = sum(Zoop_biomass, na.rm=T),
            Zoop_len_avg = mean(Zoop_len_avg, na.rm=T)) %>% 
  ungroup() 


############
# aggregate to genus_sp (from year of counting) and lifestage2 (w/o younger older)
############

# just 95-pres
LEPASgenSp <- dbGetQuery(lpdb, "SELECT 
                  ZT.Genus_sp_lifestage,
                  ZT.Genus_sp, 
                  biop_152_codes,
                  biop_152_names
                  FROM Zoop_taxa_groups ZT") %>% 
  # has some duplicate values due to younger/older which need to be removed
  distinct()

FTG2 <- FTG1 %>% 
  left_join(LEPASgenSp, by = "Genus_sp_lifestage") %>% 
  mutate(across(c(Genus_sp, biop_152_codes, biop_152_names), factor)) %>% 
  # grouping by Smp ID and genus/sp, rest along for ride
  # this summarizes to 95 to pres aggregating across eggs no eggs
  group_by(Sample_ID, Genus_sp, Life_stage2, Sample_date, Sample_site, biop_152_codes, biop_152_names) %>% 
  summarize(Number_counted = sum(Number_counted, na.rm=T),
            Zoop_density = sum(Zoop_density, na.rm=T),
            Zoop_biomass = sum(Zoop_biomass, na.rm=T),
            Zoop_len_avg = mean(Zoop_len_avg, na.rm=T)) %>% 
  mutate(Sample_date = as.POSIXct(Sample_date, format = "%Y-%m-%d"))


############
# check data
############

# look are these closely - is anything weird, if so chase down
# e.g, I found a typo in Genus_sp_lifestage because there were nas in the biop codes
summary(FTG2)


# are there dups
FTG2c <- FTG2 %>% 
  mutate(key = paste0(Sample_ID, "_", Genus_sp, "_", Life_stage2),
         dups = duplicated(key),
         Sample_date = as.POSIXct(Sample_date, format = "%Y-%m-%d"))

# note
FTG2c[FTG2c$dups == TRUE, ]


# summary by key
# not sure this is useful
FTG2c %>% 
  split(.$key) %>% 
  map(summary)

# quick plot to check for weird data
ggplot(FTG2 %>% 
         mutate(gsl = paste0(Genus_sp,"_",Life_stage2)), aes(y = log(Zoop_density+1), x = Sample_date, color = Sample_site)) +
  geom_point() +
  facet_wrap(vars(gsl))

ggplot(FTG2 %>% 
         mutate(gsl = paste0(Genus_sp,"_",Life_stage2)), aes(y = log(Zoop_biomass+1), x = Sample_date, color = Sample_site)) +
  geom_point() +
  facet_wrap(vars(gsl))

# Write .csv file -- change filepath as needed.
write.csv(FTG1, file.path(here::here("03_exports","FTGdata_2020.csv")))
