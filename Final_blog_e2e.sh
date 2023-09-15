#!/bin/bash

# Create the PySpark script
cat <<EOL > ingest_data.py
from pyspark.sql import SparkSession
def ingest_data(data_file_path,full_file_path):
    spark = SparkSession.builder \\
        .appName("Ingest Data") \\
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \\
        .config("spark.sql.catalog.dev", "org.apache.iceberg.spark.SparkCatalog") \\
        .config("spark.sql.catalog.dev.type", "hadoop") \\
        .config("spark.sql.catalog.dev.warehouse", "s3://testrajaliga/example-prefix/") \\
        .getOrCreate()
    df = spark.read.json(data_file_path) 
    df.createOrReplaceTempView("stg_table")

    # Get the first column name from the user-provided schema, this will be the PK
    first_column = next(iter(user_schema))
    # Dynamically build SQL query
    queryDelta = ", ".join([
    f"NewImage.{col_name}.{col_type} as {col_name}"
    for col_name, col_type in user_schema.items()
    ])

    # Use SQL to create DataFrame with user-provided schema
    queryDelta = f"Keys.{first_column}.{user_schema[first_column]} as Keys_{first_column}, " + queryDelta

    df_stg_result = spark.sql(f"SELECT {queryDelta} FROM stg_table")
    df_stg_result.show()

    df_full = spark.read.json(full_file_path)
    df_full.createOrReplaceTempView("tgt_table")

    # Use SQL to create DataFrame with user-provided schema
    queryFull = ", ".join([f"Item.{col_name}.{col_type} as {col_name}" for col_name, col_type in user_schema.items()])
    df_full_result = spark.sql(f"SELECT {queryFull} FROM tgt_table")
    df_full_result.show()

    # Write to Iceberg tables
    df_stg_result.writeTo("dev.db.inventory_delta").using("iceberg").createOrReplace()
    df_full_result.writeTo("dev.db.inventory_full").using("iceberg").createOrReplace()

    # Merge incremental data into the full table
    # Format the SQL query first
    merge_query = """
    MERGE INTO dev.db.inventory_full AS target
    USING dev.db.inventory_delta AS source
    ON target.{0} = source.Keys_{0}
    WHEN MATCHED AND source.Keys_{0} is null THEN DELETE
    WHEN MATCHED THEN UPDATE SET *
    WHEN NOT MATCHED THEN INSERT *
    """.format(first_column)
    spark.sql(merge_query)

# User-provided schema: key is column name, value is data type
user_schema = {
    "product_id": "S",
    "quantity": "N",
    "remaining_count": "N",
    "inventory_date": "S",
    "price": "S",
    "product_name": "S"
}

if __name__ == "__main__":
    import sys
    data_file_path = sys.argv[1]
    full_file_path = "s3://kp-data/OnlineCompany-inventory/AWSDynamoDB/01694560594775-69da9d34/data/*.json.gz"
    ingest_data(data_file_path,full_file_path)
EOL

# Function to read metadata from S3 and get the data file path
# Script assumes necessary export-id is fed this to the script below
# Function to read metadata from S3 and get the data file path

read_metadata() {
local s3_path=$1
local metadata_file="manifest-files.json" 
local metadata_content=$(aws s3 cp "s3://${s3_path}/${metadata_file}" -)
local data_file_path=$(echo "$metadata_content" | jq -r '.dataFileS3Key') # Assumes metadata contains 'data_file_path'
echo "Data file is located at: s3://${s3_bucket}/${data_file_path}"
# Run PySpark script to ingest this data and create a table
spark-submit ingest_data.py "s3://${s3_bucket}/${data_file_path}"
}

# Read extractId from the user
read -p "Enter the extractId: " extractId
# Build the S3 path based on the provided extractId
s3_bucket="kp-data"
s3_path="kp-data/OnlineCompany-inventory/AWSDynamoDB/${extractId}" # Replace with your actual bucket and prefix
# Read metadata and get the data file path
read_metadata "$s3_path"

