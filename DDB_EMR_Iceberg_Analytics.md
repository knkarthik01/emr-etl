# Data Ingestion Pipeline with PySpark and Iceberg
## Overview
This repository contains a Bash script and a PySpark script that work together to ingest JSON data into Iceberg tables. The Bash script reads metadata from an S3 bucket, and the PySpark script takes that data, transforms it, and writes it to Iceberg tables.
## Requirements

Bash
Python
PySpark
AWS CLI
jq for JSON parsing
## Installation

Install the required Python packages:
   ```bash
   pip install pyspark
   ```

Install jq and AWS CLI:
   ```bash
   apt-get install jq
   apt-get install awscli
   ```
## How to Run

Make the Bash script executable:
    ```bash
    chmod +x your_script.sh
    ```

Run the Bash script and provide the `extractId` when prompted:
    ```bash
    ./your_script.sh
    ```
## How it Works
### Bash Script

`read_metadata()`: This function reads metadata from S3 to get the path of the data file. It then triggers the PySpark script to ingest this data and create a table.
### PySpark Script (ingest_data.py)

`ingest_data()`: This function reads JSON data from the S3 bucket, performs transformations based on the user-provided schema, and writes the transformed data into Iceberg tables.
## Configuration

`user_schema`: This is a dictionary that contains the user-provided schema. The key is the column name, and the value is the data type.
## AWS S3 Configuration
The script assumes the S3 bucket and file locations are defined within the code. Modify `s3_bucket` and `s3_path` as per your requirements.
## Notes

The script assumes that the necessary export-id is fed to the Bash script.
Make sure to configure your AWS credentials before running the script.
## Contributions
Feel free to submit pull requests or open issues to improve the code or add features.
