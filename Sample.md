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

Copy the file to your local:
https://github.com/knkarthik01/emr-etl/blob/main/Final_blog_e2e.sh

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
    chmod +x Final_blog_e2e.sh
    ```

Run the Bash script and provide the `extractId` when prompted:
    ```bash
    ./Final_blog_e2e.sh.sh
    ```
## How it Works
### Bash Script

`read_metadata()`: This function reads metadata from S3 to get the path of the data file. It then triggers the PySpark script to ingest this data and create a table.
### PySpark Script (ingest_data.py)

`ingest_data()`: This function reads JSON data from the S3 bucket, performs transformations based on the user-provided schema, and writes the transformed data into Iceberg tables.

### Full Table Load: load_full_table.py
```python
from pyspark.sql import SparkSession
import sys
def load_full_table(data_file_path, user_schema):
    spark = SparkSession.builder \
        .appName("Load Full Table") \
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
        .config("spark.sql.catalog.dev", "org.apache.iceberg.spark.SparkCatalog") \
        .config("spark.sql.catalog.dev.type", "hadoop") \
        .config("spark.sql.catalog.dev.warehouse", "s3://<YOUR-BUCKET>/example-prefix/") \
        .getOrCreate()
    df = spark.read.json(data_file_path)
    df.createOrReplaceTempView("full_table")
    query = ", ".join([f"Item.{col}.{attr['type']} as {col}" for col, attr in user_schema.items()])
    df_result = spark.sql(f"SELECT {query} FROM full_table")
    df_result.show()
    df_result.writeTo("dev.db.inventory_full").using("iceberg").createOrReplace()
if __name__ == "__main__":
    data_file_path = sys.argv[1]
    user_schema = {
        "product_id": {"type": "S", "key": "PK"},
        "quantity": {"type": "N", "key": None},
        # ... (other columns)
    }
    load_full_table(data_file_path, user_schema)
```
### Incremental Load: load_incremental.py
```python
from pyspark.sql import SparkSession
import sys
def load_incremental(data_file_path, user_schema):
    spark = SparkSession.builder \
        .appName("Load Incremental Data") \
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
        .config("spark.sql.catalog.dev", "org.apache.iceberg.spark.SparkCatalog") \
        .config("spark.sql.catalog.dev.type", "hadoop") \
        .config("spark.sql.catalog.dev.warehouse", "s3://<YOUR-BUCKET>/example-prefix/") \
        .getOrCreate()
    df = spark.read.json(data_file_path)
    df.createOrReplaceTempView("incremental_table")
    query = ", ".join([f"NewImage.{col}.{attr['type']} as {col}" for col, attr in user_schema.items()])
    df_result = spark.sql(f"SELECT {query} FROM incremental_table")
    df_result.show()
    df_result.writeTo("dev.db.inventory_delta").using("iceberg").createOrReplace()
    # Add your merge logic here, similar to the previous script
if __name__ == "__main__":
    data_file_path = sys.argv[1]
    user_schema = {
        "product_id": {"type": "S", "key": "PK"},
        "quantity": {"type": "N", "key": None},
        # ... (other columns)
    }
    load_incremental(data_file_path, user_schema)
```
### Usage
For the full table load:
```bash
spark-submit load_full_table.py [path_to_full_data_file]
```
For the incremental load:
```bash
spark-submit load_incremental.py [path_to_incremental_data_file]
```



## Configuration

`user_schema`: This is a dictionary that contains the user-provided schema. The key is the column name, and the value is the data type.
## AWS S3 Configuration
The script assumes the S3 bucket and file locations are defined within the code. Modify `s3_bucket` and `s3_path` as per your requirements.
## Notes

The script assumes that the necessary export-id is fed to the Bash script.
Make sure to configure your AWS credentials before running the script.
## Contributions
Feel free to submit pull requests or open issues to improve the code or add features.
