(* autogenerated from mailboat *)
From RecoveryRefinement.Goose Require Import base.

Module partialFile.
  Record t {model:GoModel} := mk {
    off: uint64;
    data: slice.t byte;
  }.
  Arguments mk {model}.
  Global Instance t_zero {model:GoModel} : HasGoZero t := mk (zeroValue _) (zeroValue _).
End partialFile.

Definition GetUserDir {model:GoModel} (user:uint64) : proc string :=
  Ret ("user" ++ uint64_to_string user).

Definition SpoolDir : string := "spool".

Definition NumUsers : uint64 := 100.

Definition readMessage {model:GoModel} (userDir:string) (name:string) : proc string :=
  f <- FS.open userDir name;
  fileContents <- Data.newPtr (slice.t byte);
  initData <- Data.newSlice byte 0;
  _ <- Loop (fun pf =>
        buf <- FS.readAt f pf.(partialFile.off) 512;
        newData <- Data.sliceAppendSlice pf.(partialFile.data) buf;
        if compare_to (slice.length buf) 512 Lt
        then
          _ <- Data.writePtr fileContents newData;
          LoopRet tt
        else
          Continue {| partialFile.off := pf.(partialFile.off) + slice.length buf;
                      partialFile.data := newData; |}) {| partialFile.off := 0;
           partialFile.data := initData; |};
  fileData <- Data.readPtr fileContents;
  fileStr <- Data.bytesToString fileData;
  _ <- FS.close f;
  Ret fileStr.

Module Message.
  Record t {model:GoModel} := mk {
    Id: string;
    Contents: string;
  }.
  Arguments mk {model}.
  Global Instance t_zero {model:GoModel} : HasGoZero t := mk (zeroValue _) (zeroValue _).
End Message.

(* Pickup reads all stored messages and acquires a per-user lock. *)
Definition Pickup {model:GoModel} (user:uint64) : proc (slice.t Message.t) :=
  ls <- Globals.getX;
  l <- Data.sliceRead ls user;
  _ <- Data.lockAcquire l Writer;
  userDir <- GetUserDir user;
  names <- FS.list userDir;
  messages <- Data.newPtr (slice.t Message.t);
  initMessages <- Data.newSlice Message.t 0;
  _ <- Data.writePtr messages initMessages;
  _ <- Loop (fun i =>
        if i == slice.length names
        then LoopRet tt
        else
          name <- Data.sliceRead names i;
          msg <- readMessage userDir name;
          oldMessages <- Data.readPtr messages;
          newMessages <- Data.sliceAppend oldMessages {| Message.Id := name;
             Message.Contents := msg; |};
          _ <- Data.writePtr messages newMessages;
          Continue (i + 1)) 0;
  msgs <- Data.readPtr messages;
  Ret msgs.

Definition createTmp {model:GoModel} : proc (File * string) :=
  initID <- Data.randomUint64;
  finalFile <- Data.newPtr File;
  finalName <- Data.newPtr string;
  _ <- Loop (fun id =>
        let fname := uint64_to_string id in
        let! (f, ok) <- FS.create SpoolDir fname;
        if ok
        then
          _ <- Data.writePtr finalFile f;
          _ <- Data.writePtr finalName fname;
          LoopRet tt
        else
          newID <- Data.randomUint64;
          Continue newID) initID;
  f <- Data.readPtr finalFile;
  name <- Data.readPtr finalName;
  Ret (f, name).

Definition writeTmp {model:GoModel} (data:slice.t byte) : proc string :=
  let! (f, name) <- createTmp;
  _ <- Loop (fun buf =>
        if compare_to (slice.length buf) 4096 Lt
        then
          _ <- FS.append f buf;
          LoopRet tt
        else
          _ <- FS.append f (slice.take 4096 buf);
          Continue (slice.skip 4096 buf)) data;
  _ <- FS.close f;
  Ret name.

(* Deliver stores a new message.
   Does not require holding the per-user pickup/delete lock. *)
Definition Deliver {model:GoModel} (user:uint64) (msg:slice.t byte) : proc unit :=
  userDir <- GetUserDir user;
  tmpName <- writeTmp msg;
  initID <- Data.randomUint64;
  _ <- Loop (fun id =>
        ok <- FS.link SpoolDir tmpName userDir ("msg" ++ uint64_to_string id);
        if ok
        then LoopRet tt
        else
          newID <- Data.randomUint64;
          Continue newID) initID;
  FS.delete SpoolDir tmpName.

(* Delete deletes a message for the current user.
   Requires the per-user lock, acquired with pickup. *)
Definition Delete {model:GoModel} (user:uint64) (msgID:string) : proc unit :=
  userDir <- GetUserDir user;
  FS.delete userDir msgID.

(* Lock acquires the lock for the current user *)
Definition Lock {model:GoModel} (user:uint64) : proc unit :=
  locks <- Globals.getX;
  l <- Data.sliceRead locks user;
  Data.lockAcquire l Writer.

(* Unlock releases the lock for the current user. *)
Definition Unlock {model:GoModel} (user:uint64) : proc unit :=
  locks <- Globals.getX;
  l <- Data.sliceRead locks user;
  Data.lockRelease l Writer.

Definition Open {model:GoModel} : proc unit :=
  locks <- Data.newPtr (slice.t LockRef);
  initLocks <- Data.newSlice LockRef 0;
  _ <- Data.writePtr locks initLocks;
  _ <- Loop (fun i =>
        if i == NumUsers
        then LoopRet tt
        else
          oldLocks <- Data.readPtr locks;
          l <- Data.newLock;
          newLocks <- Data.sliceAppend oldLocks l;
          _ <- Data.writePtr locks newLocks;
          Continue (i + 1)) 0;
  finalLocks <- Data.readPtr locks;
  Globals.setX finalLocks.

Definition Recover {model:GoModel} : proc unit :=
  spooled <- FS.list SpoolDir;
  Loop (fun i =>
        if i == slice.length spooled
        then LoopRet tt
        else
          name <- Data.sliceRead spooled i;
          _ <- FS.delete SpoolDir name;
          Continue (i + 1)) 0.
