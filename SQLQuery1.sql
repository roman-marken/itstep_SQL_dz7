USE master;
GO
IF EXISTS (SELECT name FROM sys.databases WHERE name = N'СпортивнийМагазин')
BEGIN
    ALTER DATABASE СпортивнийМагазин SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE СпортивнийМагазин;
END
GO
CREATE DATABASE СпортивнийМагазин;
GO
USE СпортивнийМагазин;
GO
CREATE TABLE ВидиТоварів (
    ID_виду INT IDENTITY(1,1) PRIMARY KEY,
    Назва_виду NVARCHAR(50) NOT NULL UNIQUE
);
CREATE TABLE Співробітники (
    ID_співробітника INT IDENTITY(1,1) PRIMARY KEY,
    ПІБ NVARCHAR(100) NOT NULL,
    Посада NVARCHAR(50) NOT NULL,
    Дата_прийняття DATE NOT NULL,
    Стать CHAR(1) CHECK (Стать IN ('Ч', 'Ж')),
    Зарплата DECIMAL(10, 2) NOT NULL CHECK (Зарплата > 0)
);
CREATE TABLE Клієнти (
    ID_клієнта INT IDENTITY(1,1) PRIMARY KEY,
    ПІБ NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100),
    Контактний_телефон NVARCHAR(20),
    Стать CHAR(1) CHECK (Стать IN ('Ч', 'Ж')),
    Відсоток_знижки DECIMAL(5,2) DEFAULT 0,
    Чи_підписаний_на_розсилку BIT DEFAULT 0,
    CONSTRAINT UQ_Клієнти_ПІБ_Email UNIQUE (ПІБ, Email)
);
CREATE TABLE Товари (
    ID_товару INT IDENTITY(1,1) PRIMARY KEY,
    Назва_товару NVARCHAR(100) NOT NULL,
    ID_виду INT NOT NULL FOREIGN KEY REFERENCES ВидиТоварів(ID_виду),
    Кількість_в_наявності INT NOT NULL CHECK (Кількість_в_наявності >= 0),
    Собівартість DECIMAL(10, 2) NOT NULL CHECK (Собівартість > 0),
    Виробник NVARCHAR(100) NOT NULL,
    Ціна_продажу DECIMAL(10, 2) NOT NULL CHECK (Ціна_продажу > 0)
);
CREATE TABLE Продажі (
    ID_продажу INT IDENTITY(1,1) PRIMARY KEY,
    ID_товару INT NOT NULL FOREIGN KEY REFERENCES Товари(ID_товару),
    Кількість INT NOT NULL CHECK (Кількість > 0),
    Ціна_продажу_фіксована DECIMAL(10, 2) NOT NULL,
    Дата_продажу DATETIME NOT NULL DEFAULT GETDATE(),
    ID_співробітника INT NOT NULL FOREIGN KEY REFERENCES Співробітники(ID_співробітника),
    ID_клієнта INT NULL FOREIGN KEY REFERENCES Клієнти(ID_клієнта)
);
CREATE TABLE ІсторіяПродажів (
    ID_історії INT IDENTITY(1,1) PRIMARY KEY,
    ID_продажу INT NOT NULL,
    ID_товару INT NOT NULL,
    Назва_товару NVARCHAR(100) NOT NULL,
    Кількість INT NOT NULL,
    Ціна_продажу DECIMAL(10, 2) NOT NULL,
    Дата_продажу DATETIME NOT NULL,
    Продавець_ПІБ NVARCHAR(100) NOT NULL,
    Покупець_ПІБ NVARCHAR(100) NULL,
    Дата_архівації DATETIME NOT NULL DEFAULT GETDATE()
);
CREATE TABLE АрхівТоварів (
    ID_архіву INT IDENTITY(1,1) PRIMARY KEY,
    ID_товару INT NOT NULL,
    Назва_товару NVARCHAR(100) NOT NULL,
    Виробник NVARCHAR(100) NOT NULL,
    Собівартість DECIMAL(10, 2) NOT NULL,
    Остання_ціна_продажу DECIMAL(10, 2) NOT NULL,
    Дата_продажу_останньої_одиниці DATETIME NOT NULL,
    Дата_архівації DATETIME NOT NULL DEFAULT GETDATE()
);
CREATE TABLE ОстанняОдиниця (
    ID_запису INT IDENTITY(1,1) PRIMARY KEY,
    ID_товару INT NOT NULL UNIQUE,
    Назва_товару NVARCHAR(100) NOT NULL,
    Виробник NVARCHAR(100) NOT NULL,
    Кількість INT NOT NULL CHECK (Кількість = 1),
    Ціна_продажу DECIMAL(10, 2) NOT NULL,
    Дата_оновлення DATETIME NOT NULL DEFAULT GETDATE()
);
CREATE TABLE АрхівСпівробітників (
    ID_архіву INT IDENTITY(1,1) PRIMARY KEY,
    ID_співробітника INT NOT NULL,
    ПІБ NVARCHAR(100) NOT NULL,
    Посада NVARCHAR(50) NOT NULL,
    Дата_прийняття DATE NOT NULL,
    Стать CHAR(1),
    Зарплата DECIMAL(10, 2) NOT NULL,
    Дата_звільнення DATETIME NOT NULL DEFAULT GETDATE()
);
GO


CREATE TRIGGER trg_Продажі_InsertIntoHistory
ON Продажі
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO ІсторіяПродажів (ID_продажу, ID_товару, Назва_товару, Кількість, Ціна_продажу, Дата_продажу, Продавець_ПІБ, Покупець_ПІБ)
    SELECT
        i.ID_продажу,
        i.ID_товару,
        t.Назва_товару,
        i.Кількість,
        i.Ціна_продажу_фіксована,
        i.Дата_продажу,
        s.ПІБ,
        c.ПІБ
    FROM inserted i
    INNER JOIN Товари t ON i.ID_товару = t.ID_товару
    INNER JOIN Співробітники s ON i.ID_співробітника = s.ID_співробітника
    LEFT JOIN Клієнти c ON i.ID_клієнта = c.ID_клієнта;
END;
GO


CREATE TRIGGER trg_Товари_AfterUpdate_MoveToArchive
ON Товари
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(Кількість_в_наявності)
    BEGIN
        INSERT INTO АрхівТоварів (ID_товару, Назва_товару, Виробник, Собівартість, Остання_ціна_продажу, Дата_продажу_останньої_одиниці)
        SELECT
            d.ID_товару,
            d.Назва_товару,
            d.Виробник,
            d.Собівартість,
            d.Ціна_продажу,
            GETDATE()
        FROM deleted d
        INNER JOIN inserted i ON d.ID_товару = i.ID_товару
        WHERE d.Кількість_в_наявності > 0 AND i.Кількість_в_наявності = 0;
    END
END;
GO


CREATE TRIGGER trg_Клієнти_InsteadOfInsert
ON Клієнти
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE EXISTS (
            SELECT 1
            FROM Клієнти k
            WHERE k.ПІБ = i.ПІБ AND k.Email = i.Email
        )
    )
    BEGIN
        RAISERROR('Клієнт з таким ПІБ та Email вже зареєстрований.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
    INSERT INTO Клієнти (ПІБ, Email, Контактний_телефон, Стать, Відсоток_знижки, Чи_підписаний_на_розсилку)
    SELECT ПІБ, Email, Контактний_телефон, Стать, Відсоток_знижки, Чи_підписаний_на_розсилку
    FROM inserted;
END;
GO

CREATE TRIGGER trg_Клієнти_InsteadOfDelete
ON Клієнти
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    RAISERROR('Видалення клієнтів заборонено.', 16, 1);
    ROLLBACK TRANSACTION;
END;
GO


CREATE TRIGGER trg_Співробітники_InsteadOfDelete
ON Співробітники
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    

    IF EXISTS (
        SELECT 1
        FROM deleted
        WHERE YEAR(Дата_прийняття) < 2015
    )
    BEGIN
        RAISERROR('Видалення співробітників, прийнятих до 2015 року, заборонено.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
    

    INSERT INTO АрхівСпівробітників (ID_співробітника, ПІБ, Посада, Дата_прийняття, Стать, Зарплата)
    SELECT ID_співробітника, ПІБ, Посада, Дата_прийняття, Стать, Зарплата
    FROM deleted
    WHERE YEAR(Дата_прийняття) >= 2015;
    

    DELETE FROM Співробітники
    WHERE ID_співробітника IN (SELECT ID_співробітника FROM deleted WHERE YEAR(Дата_прийняття) >= 2015);
END;
GO


CREATE TRIGGER trg_Продажі_AfterInsert_UpdateClientDiscount
ON Продажі
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE k
    SET k.Відсоток_знижки = 15
    FROM Клієнти k
    WHERE k.ID_клієнта IN (
        SELECT i.ID_клієнта
        FROM inserted i
        WHERE i.ID_клієнта IS NOT NULL
    )
    AND k.Відсоток_знижки < 15
    AND (
        SELECT SUM(Кількість * Ціна_продажу_фіксована)
        FROM Продажі
        WHERE ID_клієнта = k.ID_клієнта
    ) > 50000;
END;
GO


CREATE TRIGGER trg_Товари_InsteadOfInsert
ON Товари
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    

    IF EXISTS (
        SELECT 1
        FROM inserted
        WHERE Виробник = N'Спорт, сонце і штанга'
    )
    BEGIN
        RAISERROR('Додавання товарів фірми "Спорт, сонце і штанга" заборонено.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
    

    UPDATE t
    SET t.Кількість_в_наявності = t.Кількість_в_наявності + i.Кількість_в_наявності
    FROM Товари t
    INNER JOIN inserted i ON t.Назва_товару = i.Назва_товару AND t.Виробник = i.Виробник
    WHERE t.Собівартість = i.Собівартість AND t.Ціна_продажу = i.Ціна_продажу;
    

    INSERT INTO Товари (Назва_товару, ID_виду, Кількість_в_наявності, Собівартість, Виробник, Ціна_продажу)
    SELECT
        i.Назва_товару,
        i.ID_виду,
        i.Кількість_в_наявності,
        i.Собівартість,
        i.Виробник,
        i.Ціна_продажу
    FROM inserted i
    LEFT JOIN Товари t ON i.Назва_товару = t.Назва_товару AND i.Виробник = t.Виробник
                      AND i.Собівартість = t.Собівартість AND i.Ціна_продажу = t.Ціна_продажу
    WHERE t.ID_товару IS NULL;
END;
GO


CREATE TRIGGER trg_Товари_AfterUpdate_LastUnit
ON Товари
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(Кількість_в_наявності)
    BEGIN
        MERGE INTO ОстанняОдиниця AS target
        USING (
            SELECT
                i.ID_товару,
                i.Назва_товару,
                i.Виробник,
                i.Кількість_в_наявності,
                i.Ціна_продажу
            FROM inserted i
            INNER JOIN deleted d ON i.ID_товару = d.ID_товару
            WHERE i.Кількість_в_наявності = 1 AND d.Кількість_в_наявності > 1
        ) AS source (ID_товару, Назва_товару, Виробник, Кількість, Ціна_продажу)
        ON target.ID_товару = source.ID_товару
        WHEN MATCHED THEN
            UPDATE SET
                Назва_товару = source.Назва_товару,
                Виробник = source.Виробник,
                Кількість = source.Кількість,
                Ціна_продажу = source.Ціна_продажу,
                Дата_оновлення = GETDATE()
        WHEN NOT MATCHED THEN
            INSERT (ID_товару, Назва_товару, Виробник, Кількість, Ціна_продажу)
            VALUES (source.ID_товару, source.Назва_товару, source.Виробник, source.Кількість, source.Ціна_продажу);
        
        DELETE FROM ОстанняОдиниця
        WHERE ID_товару IN (
            SELECT i.ID_товару
            FROM inserted i
            WHERE i.Кількість_в_наявності != 1
        );
    END
END;
GO


CREATE TRIGGER trg_Співробітники_InsteadOfInsert
ON Співробітники
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @currentSellersCount INT;
    
    SELECT @currentSellersCount = COUNT(*)
    FROM Співробітники
    WHERE Посада = N'Продавець';
    
    IF @currentSellersCount + (SELECT COUNT(*) FROM inserted WHERE Посада = N'Продавець') > 6
    BEGIN
        RAISERROR('Не можна додати нового продавця. Ліміт (6) вичерпано.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
    
    INSERT INTO Співробітники (ПІБ, Посада, Дата_прийняття, Стать, Зарплата)
    SELECT ПІБ, Посада, Дата_прийняття, Стать, Зарплата
    FROM inserted;
END;
GO