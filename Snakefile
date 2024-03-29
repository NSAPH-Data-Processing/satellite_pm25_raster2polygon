import yaml
from src.aggregate_pm25 import available_shapefile_year

conda: "requirements.yaml"
configfile: "conf/config.yaml"

defaults_dict = {key: value for d in config['defaults'] if isinstance(d, dict) for key, value in d.items()}

polygon_name=config["polygon_name"]
temporal_freq = config['temporal_freq']

shapefiles_cfg = yaml.safe_load(open(f"conf/shapefiles/shapefiles.yaml", 'r'))
satellite_pm25_cfg = yaml.safe_load(open(f"conf/satellite_pm25/satellite_pm25.yaml", 'r'))

shapefile_years_list = list(shapefiles_cfg[polygon_name].keys())

years_list = list(range(1998, 2022 + 1))
months_list = "01" if temporal_freq == 'annual' else [str(i).zfill(2) for i in range(1, 12 + 1)]

# == Define rules ==
rule all:
    input:
        expand(f"data/output/satellite_pm25_raster2polygon/{temporal_freq}/satellite_pm25_{polygon_name}_" + 
                ("{year}.parquet" if temporal_freq == 'annual' else "{year}_{month}.parquet"), 
            year=years_list,
            month=months_list
        )

rule download_shapefiles:
    output:
        f"data/input/shapefiles/shapefile_{polygon_name}_" + "{shapefile_year}/shapefile.shp" 
    shell:
        f"python src/download_shapefile.py polygon_name={polygon_name} " + "shapefile_year={wildcards.shapefile_year}"

rule download_satellite_pm25:
    output:
        expand(
            f"data/input/satellite_pm25/{temporal_freq}/{satellite_pm25_cfg[temporal_freq]['file_prefix']}." + 
            ("{year}01-{year}12.nc" if temporal_freq == 'annual' else "{year}{month}-{year}{month}.nc"), 
            year=years_list,
            month=months_list)
    log:    
        f"logs/download_satellite_pm25_{temporal_freq}.log"
    shell:
        f"python src/download_pm25.py temporal_freq={temporal_freq} " + " &> {log}"

def get_shapefile_input(wildcards):
    shapefile_year = available_shapefile_year(int(wildcards.year), shapefile_years_list)
    return f"data/input/shapefiles/shapefile_{polygon_name}_{shapefile_year}/shapefile.shp"

rule aggregate_pm25:
    input:
        get_shapefile_input,
        expand(
            f"data/input/satellite_pm25/{temporal_freq}/{satellite_pm25_cfg[temporal_freq]['file_prefix']}." + 
            ("{{year}}01-{{year}}12.nc" if temporal_freq == 'annual' else "{{year}}{month}-{{year}}{month}.nc"), 
            month=months_list
        )

    output:
        expand(
            f"data/output/satellite_pm25_raster2polygon/{temporal_freq}/satellite_pm25_{polygon_name}_" + 
            ("{{year}}.parquet" if temporal_freq == 'annual' else "{{year}}_{month}.parquet"), 
            month=months_list  # we only want to expand months_list and keep year as wildcard
        )
    log:
        f"logs/satellite_pm25_{polygon_name}_{{year}}.log"
    shell:
        (
            f"PYTHONPATH=. python src/aggregate_pm25.py polygon_name={polygon_name} temporal_freq={temporal_freq} " + 
            ("year={wildcards.year}" if temporal_freq == 'annual' else "year={wildcards.year}") +
            " &> {log}"
        )
