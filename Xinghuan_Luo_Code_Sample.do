
********************************************************************
* To be consistent with the Data Task instruction, I started with secion 2. 

* Theis code file has 3 parts:
* - Part 2 Data Cleaning
* - Part 3 Analyze Patterns across 4 Years
* - Part 4 Analyze Pattern within Each Year

************************Part 2 Data Cleaning***********************
clear
set more off
set varabbrev off

// If the reader wants to replicate the results, he/she just needs to change this global path and put the data in raw_data file. 
global code_sample "D:/OneDrive - The University of Chicago/2021 Fall/job searching/BFI/Dube"

// I defined path to save the results 
local top_file `""scripts" "results" "raw_data""'
foreach file_path in `top_file' {
	cap mkdir "$code_sample/`file_path'"
	global `file_path' "$code_sample/`file_path'"
}

local data_path `""car_data" "market_data" "merged_data""'
foreach data in `data_path' {
	cap mkdir "$raw_data/`data'"
	global `data' "$raw_data/`data'"
}

local results_path `""tables" "graphs" "latex" "logs""'
foreach result in `results_path' {
	cap mkdir "$results/`result'"
	global `result' "$results/`result'"
}

cap log close
log using "$logs/Xinghuan_log.log", replace 

// I used csvconvert to merge all car data and market data into two separate dta file. 
cap ssc install csvconvert
csvconvert $car_data, replace output_file(all_car_data.dta) output_dir($merged_data)
csvconvert $market_data, replace output_file(all_market_data.dta) output_dir($merged_data)

// I cleaned the two new data set below and modified variables for merging them together later
use "$merged_data/all_market_data.dta", clear
drop _csvfile

// I converted the abbreviation of country name to the full name 
local country_list `""Belgium" "France" "Germany" "Italy" "United Kingdom""'
foreach country in `country_list' {
	replace ma = "`country'" if ma == substr("`country'", 1, 1)
}
save "$merged_data/all_market_data.dta", replace 


use "$merged_data/all_car_data.dta", clear
drop _csvfile
replace ma = "United Kingdom" if ma == "UK"
replace ye = 1900 + ye

// In the data_description.text, it says year = first dimension, market = second dimension and model = third dimension. 
// So, I followed this guidance to make the panel data set. 
// Because I did not find variable "co" (model code) mentioned in the data_description.text, I used variable "model" instead. 
merge m:1 ye ma using "$merged_data/all_market_data", nogen
order model, before(loc)

// I transformed all li(measure of fuel consumption) variables into number so that I could fill in the missing values
// I first filled in the missing values in li and used the value of li to fill in other missing values. 
destring li*, replace force
replace li = li1 + li2 + li3 if mi(li) & !mi(li1, li2, li3)

foreach var in li1 li2 li3 {
	replace `var' = 0 if mi(`var')
}
foreach var in li1 li2 li3 {
	replace `var' = li*3 - (li1 + li2 + li3) if `var' == 0
}

save "$merged_data/cleaning_done_data.dta", replace

************************Part 3 Data Exploration ***********************
// I saved the original data set so that I could use it later
tempfile original_data
save `original_data'

// I created two tempfiles, only_1970 and only_1990. 
preserve
tempfile only_1970
keep if ye == 1970
save `only_1970'
restore

preserve
tempfile only_1990
keep if ye == 1990
save `only_1990'
restore

// Question 1
// I generated the required variables in these two tempfiles and merge them together later
cap ssc install asgen
foreach file in `only_1970' `only_1990' {
	use `file', clear

	su qu
	local q_total r(sum)
	gen hp_qu = hp * qu / `q_total'
	
	pctile hp_pct = hp, nq(10)
	xtile decile_grp = hp, cut(hp_pct)

	bysort decile_grp: egen avg_fuel = total(hp_qu)

	bysort decile_grp: egen mid_hp = median(hp)
	bysort decile_grp: egen num_obs = count(avg_fuel)
	gen log_hp = log(hp)
	reg avg_fuel hp log_hp [pweight=qu]	
	predict y_hat
	save `file', replace 
}

use `only_1970', clear
append using `only_1990'

// Because observations in the same decile group have same avg_fuel and mid_hp value, then if I make the scatter plot directly, they will just overlapped with each other. 
// I first extracted unique values from the orignal data set and then appended it back. 
tempfile all_70_90
save `all_70_90'

// I add unique as a prefix to each variable's name so that they will not be replaced by the same variables in the original data set. 
tempfile prepare_scatter
collapse (mean) avg_fuel mid_hp num_obs, by(ye decile_grp)
foreach var of varlist _all {
	rename `var' unique_`var'
}
save `prepare_scatter'

use `all_70_90', clear
merge 1:1 _n using `prepare_scatter', nogen


// Question 2
// I created the required graph in question 2
local scatter_settings msize(small) jitter(4)
twoway (scatter unique_avg_fuel unique_mid_hp if unique_ye == 1970 [fweight=unique_num_obs], `scatter_settings' color(blue)) ///
	   (scatter unique_avg_fuel unique_mid_hp if unique_ye == 1990 [fweight=unique_num_obs], `scatter_settings' color(dkorange)), ///
	   graphregion(color(white)) legend(label(1 1970) label(2 1990) nobox region(lcolor(white)))  xlabel(15(15)120 ,labsize(small)) ///
	   xtitle("Midpoint of Each Horsepower Decile") ytitle("Sales-Weighted Average of Fuel Consumption") ///
	   note("The relative size of the each scatter point represents the number of observations it has.") 
graph export "$graphs/only_scatter.png", as(png) replace 

// Question 3
// I created the required graph in question 3
local scatter_settings msize(small) jitter(4)
local line_settings lcolor(gs0) sort
twoway (scatter unique_avg_fuel unique_mid_hp if unique_ye == 1970 [fweight=unique_num_obs], `scatter_settings' color(blue)) ///
	   (line y_hat hp  if ye == 1970,  `line_settings' lpattern(shortdash dot)) ///
	   (scatter unique_avg_fuel unique_mid_hp if unique_ye == 1990 [fweight=unique_num_obs], `scatter_settings' color(dkorange)) ///
	   (line y_hat hp  if ye == 1990, `line_settings' lpattern(longdash)), ///
		xlabel(15(15)150, labsize(small)) ylabel(5(2.5)15) graphregion(color(white)) ///
		legend(label(1 1970 ) label(2 1970 ) label(3 1990) label(4 1990) nobox region(lcolor(white))) ///
		xtitle("Horsepower") ytitle("Sales-Weighted Average of Fuel Consumption" ) ///
		note("Both scatter points and fitted lines describe the relationship between horsepower and fuel consumption. " ///
			 "The fitted lines are generated by the linear regression with sales as sample weights. " ///
			 "The relative size of the each scatter point represents the number of observations it has.")
graph export "$graphs/scatter_fitted.png", as(png) replace 

// Question 6
// I first collapsed the data set and used texsave to create the required graph in question 6
collapse (min) min_hp = hp (max) max_hp = hp (mean) mean_fuel = avg_fuel (count) num_obs = avg_fuel if ye == 1990, by(decile_grp)
egen hp_interval = concat(min_hp max_hp), punct("--")
drop decile_grp min_hp max_hp

order hp_interval, first
label var hp_interval "Horsepower(kW)"
label var mean_fuel "Fuel Consumption"
label var num_obs "\(N\)"

replace mean_fuel = round(mean_fuel, .01)

local title title("Sales-Weighted Average of Fuel Consumption by Decile of Horsepower in 1990")
local footnote footnote("Notes: Horsepower column represents the range of horsepower in each decile group. Fuel Consumption column represents the sales-weighted average of fuel consumption (liter per km) of each decile gruop.")
texsave using "$tables/summarized_table.tex", varlabels nofix replace `footnote' frag `title' marker(tab: tb1)


************************Part 4 Estimation and Causal Inference ***********************
use `original_data', clear

label var ye "Year"
label var li "Fuel Consumption"
label var eurpr "Price in Euro"

// Question 1 
// I generated Y_ijt
bysort ye ma: gen N_jt = pop / 4
bysort ye ma model: egen total_model_sale = total(qu)
bysort ye ma : egen total_car_sale = total(qu)
gen S_ijt = total_model_sale / N_jt 
gen S_0jt = 1 - (total_car_sale / N_jt)

bysort ye ma model: gen Y_ijt = log(S_ijt) - log(S_0jt)

// Question 2
eststo clear
eststo model1: qui reg Y_ijt li eurpr, r

//Question 4
// I first transformed ma and model into numberic variables so that I could include them as fixed effecs in the regression
encode ma, generate(market)
encode model, generate(model_code)

label var market "Market"
label var model_code "Model Code"

eststo model2: qui reg Y_ijt li eurpr i.ye i.market i.model_code, r
esttab using "$tables/two_regressions.tex", ///
	   replace p keep(li eurpr) booktabs width(\hsize) nofloat label ///
	   mtitles("Model 1" "Model 2") nonumbers ///
	   addnotes("Model 1 is conventional OLS regression for question 2. " ///
	   "Model 2 is OLS regression with fixed effects of car model, market and year for question 3. ")


log close 
* EOF





