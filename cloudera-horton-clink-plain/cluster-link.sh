./confluent-7.4.0/bin/kafka-cluster-links --bootstrap-server 10.1.1.13:9092 -create --link chuck-link --config-file ./cluster-link.properties --consumer-group-filters-json-file ./consumer-groups.json