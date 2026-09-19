//******************************************************************************
// Copyright (c) 2023 Autodesk Inc. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************

#include <TwkUtil/FileLogger.h>
#include <TwkUtil/EnvVar.h>
#include <QtCore/QtCore>
#include <spdlog/spdlog.h>
#include <spdlog/async.h>
#include <spdlog/sinks/rotating_file_sink.h>
#include <boost/algorithm/string.hpp>
#include <iostream>
#include <ostream>

namespace TwkUtil
{

    static ENVVAR_STRING(evFileLogLevel, "RV_FILE_LOG_LEVEL", "debug");
    static ENVVAR_INT(evFileLogSize, "RV_FILE_LOG_SIZE",
                      1024 * 1024 * 5); // Default: 5MB
    static ENVVAR_INT(evFileLogNumFiles, "RV_FILE_LOG_NUM_FILES", 2);
    static ENVVAR_BOOL(evFileLogSynchronous, "RV_FILE_LOG_SYNCHRONOUS", false);

    FileLogger::FileLogger()
        : m_logger(nullptr)
    {
#if defined(PLATFORM_DARWIN)
        QString qLogDirPath = QDir::homePath() + "/Library/Logs/" + QCoreApplication::organizationName() + "/";
#else
        QString qLogDirPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/";
#endif
        if (qLogDirPath.isEmpty() || qLogDirPath == "/")
        {
            qLogDirPath = QDir::tempPath() + "/OpenUTV/";
        }

        QDir().mkpath(qLogDirPath);

        std::string logFilePath = qLogDirPath.toStdString();
        std::cout << "INFO: File logger path: " << logFilePath << '\n';

        std::string name = QCoreApplication::applicationName().toStdString();
        if (name.empty())
        {
            name = "UTV";
        }

        try
        {
            auto existing = spdlog::get(name);
            if (existing)
            {
                m_logger = existing.get();
            }
            else if (evFileLogSynchronous.getValue())
            {
                m_logger = spdlog::rotating_logger_mt(name, logFilePath.append(name + ".log"), evFileLogSize.getValue(),
                                                      evFileLogNumFiles.getValue())
                               .get();

                m_logger->flush_on(spdlog::level::trace); // All message levels will
                                                          // be flush to disk
            }
            else
            {
                m_logger = spdlog::rotating_logger_mt<spdlog::async_factory>(name, logFilePath.append(name + ".log"),
                                                                             evFileLogSize.getValue(), evFileLogNumFiles.getValue())
                               .get();
                m_logger->flush_on(spdlog::level::err);
            }

            if (m_logger)
            {
                setLogLevel(evFileLogLevel.getValue());
                m_logger->info("============ SESSION START ============\n");
            }
        }
        catch (const std::exception& e)
        {
            std::cerr << "WARNING: Failed to initialize file logger (" << e.what() << ")\n";
            m_logger = nullptr;
        }
        catch (...)
        {
            std::cerr << "WARNING: Unknown exception initializing file logger\n";
            m_logger = nullptr;
        }
    }

    FileLogger::~FileLogger()
    {
        if (m_logger)
        {
            m_logger->info("============  SESSION END  ============\n");
        }
    }

    void FileLogger::logToFile(spdlog::level::level_enum lineLevel, const std::string& line)
    {
        if (!m_logger)
        {
            return;
        }

        switch (lineLevel)
        {
        case spdlog::level::debug:
            m_logger->debug(line);
            break;
        case spdlog::level::info:
            m_logger->info(line);
            break;
        case spdlog::level::warn:
            m_logger->warn(line);
            break;
        case spdlog::level::err:
            m_logger->error(line);
            break;
        default:
            break;
        }
    }

    void FileLogger::setLogLevel(const std::string& level)
    {
        if (!m_logger)
        {
            return;
        }

        if (level == "trace")
        {
            m_logger->set_level(spdlog::level::trace);
        }
        else if (level == "debug" || level == "deb")
        {
            m_logger->set_level(spdlog::level::debug);
        }
        else if (level == "info")
        {
            m_logger->set_level(spdlog::level::info);
        }
        else if (level == "warning" || level == "warn")
        {
            m_logger->set_level(spdlog::level::warn);
        }
        else if (level == "error")
        {
            m_logger->set_level(spdlog::level::err);
        }
        else if (level == "critical")
        {
            m_logger->set_level(spdlog::level::critical);
        }
    }
} // namespace TwkUtil
