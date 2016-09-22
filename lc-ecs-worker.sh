#!/bin/bash

region=${AWS_REGION}
queue=${SQS_QUEUE_URL}
cdn_bucket=${CDN_BUCKET}

echo "Region: ${region}"

if [ -n "${region}" ]; then
    echo "ENV params found."
else
    echo "ENV params not found . Exiting."
    exit 0
fi

# Fetch messages and render them until the queue is drained.
while [ /bin/true ]; do
    # Fetch the next message and extract the S3 URL
    echo "Fetching messages from SQS queue: ${queue}..."
    result=$( \
        aws sqs receive-message \
            --queue-url ${queue} \
            --region ${region} \
            --wait-time-seconds 1 \
            --max-number-of-messages 1 \
            --query Messages[0].[Body,ReceiptHandle] \
        | sed -e 's/^"\(.*\)"$/\1/'\
    )

    echo "Result: ${result}"

    if [ "${result}" = "null" ]; then
        echo "No messages left in queue. Exiting."
        exit 0
    else
        echo "Message: ${result}."

        receipt_handle=$(echo ${result} | sed -e 's/^.*"\([^"]*\)"\s*\]$/\1/')
        echo "Receipt handle: ${receipt_handle}."

        key=$(echo ${result} | sed -e 's/^.*\\"key\\":\s*\\"\([^\\]*\)\\".*$/\1/')
        FILE_URL=$(echo ${result} | sed -e 's/^.*\\"url\\":\s*\\"\([^\\]*\)\\".*$/\1/')
        echo "Key: ${key}."
        echo "Key: ${FILE_URL}."

        base=${key%.*}
        ext=${key##*.}

        if [ -n "${result}" -a -n "${receipt_handle}" -a -n "${key}" ]; then
            mkdir -p work
            cp clean.js work/

            pushd work

            echo "Processing ${key}...url"
            echo "Creating audiowaveform for ${FILE_URL}"

            curl -o file.mp3 -L $FILE_URL
            base="waveform"

            # audiowaveform -i some-file.mp3 --pixels-per-second 10 -b 8 -o some-file.json

            if audiowaveform -i file.mp3 -o ${base}.dat --pixels-per-second 10 -b 8; then
                echo "Copying result .dat ${base}.dat to s3://${cdn_bucket}/${key}/${base}.dat..."
                aws s3 cp ${base}.dat  s3://${cdn_bucket}/${key}/${base}.dat
                if audiowaveform -i ${base}.dat -o ${base}.png --pixels-per-second 10 -b 8 --no-axis-labels; then
                    if [ -f ${base}.png ]; then
                        echo "Copying result image ${base}.png to s3://${cdn_bucket}/${key}/${base}.png..."
                        aws s3 cp ${base}.png s3://${cdn_bucket}/${key}/${base}.png
                    else
                        echo "ERROR: audiowaveform source did not generate ${base}.png image."
                    fi
                else
                    echo "ERROR: audiowaveform source did not render png successfully."
                fi

                if audiowaveform -i ${base}.dat -o ${base}.json --pixels-per-second 10 -b 8; then
                    if [ -f ${base}.json ]; then
                        echo "Copying result json ${base}.json to s3://${cdn_bucket}/${key}/${base}.json..."
                        aws s3 cp ${base}.json s3://${cdn_bucket}/${key}/${base}.json
                    else
                        echo "ERROR: audiowaveform source did not generate ${base}.json image."
                    fi
                else
                    echo "ERROR: audiowaveform source did not render png successfully."
                fi
            else
                echo "ERROR: audiowaveform source did not generate dat successfully."
            fi

            echo "Cleaning up..."
            popd
            /bin/rm -rf work

            echo "Deleting message..."
            aws sqs delete-message \
                --queue-url ${queue} \
                --region ${region} \
                --receipt-handle "${receipt_handle}"
        else
            echo "ERROR: Could not extract S3 bucket and key from SQS message."
        fi
    fi
done
