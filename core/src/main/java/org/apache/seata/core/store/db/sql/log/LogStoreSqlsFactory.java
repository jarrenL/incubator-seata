/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.seata.core.store.db.sql.log;

import org.apache.seata.common.loader.EnhancedServiceLoader;
import org.apache.seata.common.util.CollectionUtils;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class LogStoreSqlsFactory {

    private static final String DB_TYPE_GAUSSDB = "gaussdb";
    private static final String DB_TYPE_POSTGRESQL = "postgresql";

    private static Map<String, LogStoreSqls> LOG_STORE_SQLS_MAP = new ConcurrentHashMap<>();

    /**
     * get the log store sqls
     * @param dbType the db type
     * @return the LogStoreSqls
     */
    public static LogStoreSqls getLogStoreSqls(String dbType) {
        String finalDbType = DB_TYPE_GAUSSDB.equalsIgnoreCase(dbType) ? DB_TYPE_POSTGRESQL : dbType;
        return CollectionUtils.computeIfAbsent(
                LOG_STORE_SQLS_MAP,
                finalDbType,
                key -> EnhancedServiceLoader.load(LogStoreSqls.class, finalDbType.toLowerCase()));
    }
}
