import Foundation

/// Let AppKit own replacement and undo ranges, including inserted separators.
nonisolated final class MacAmountEditingFormatter: Formatter, @unchecked Sendable {
    let grouping:String
    init(grouping:String){self.grouping=grouping;super.init()}
    required init?(coder:NSCoder){grouping=coder.decodeObject(forKey:"grouping") as? String ?? "comma";super.init(coder:coder)}
    override func encode(with coder:NSCoder){super.encode(with:coder);coder.encode(grouping,forKey:"grouping")}
    override func copy(with zone:NSZone? = nil)->Any {MacAmountEditingFormatter(grouping:grouping)}
    override func string(for obj:Any?)->String? {obj as? String}
    override func getObjectValue(_ obj:AutoreleasingUnsafeMutablePointer<AnyObject?>?,for string:String,errorDescription error:AutoreleasingUnsafeMutablePointer<NSString?>?)->Bool {
        obj?.pointee=string as NSString;return true
    }
    override func isPartialStringValid(_ partialStringPtr:AutoreleasingUnsafeMutablePointer<NSString>,proposedSelectedRange selection:NSRangePointer?,originalString original:String,originalSelectedRange originalSelection:NSRange,errorDescription error:AutoreleasingUnsafeMutablePointer<NSString?>?)->Bool {
        let value=partialStringPtr.pointee as String,separator=grouping == "space" ? " ":","
        let old=Array(original),new=Array(value)
        var prefix=0,suffix=0
        while prefix<min(old.count,new.count),old[prefix]==new[prefix]{prefix+=1}
        while suffix<min(old.count,new.count)-prefix,old[old.count-1-suffix]==new[new.count-1-suffix]{suffix+=1}
        let ordinary=max(old.count-prefix-suffix,new.count-prefix-suffix)<=1
        let grouped=grouping != "none" && value.contains(separator)
        let raw=grouped ? value.replacingOccurrences(of:separator,with:""):value
        guard raw.range(of:#"^[0-9]*(\.[0-9]*)?$"#,options:.regularExpression) != nil,
              !grouped || ordinary || MacNumberInput.raw(value,grouping:grouping) != value else {
            partialStringPtr.pointee=original as NSString;selection?.pointee=originalSelection;return false
        }
        let display=MacNumberInput.display(raw,grouping:grouping)
        guard display != value else{return true}
        let cursor=min(selection?.pointee.location ?? value.count,value.count)
        let logical=value.prefix(cursor).filter{String($0) != separator}.count
        var count=0,offset=0
        for character in display {
            if count==logical {break}
            offset+=1;if String(character) != separator {count+=1}
        }
        partialStringPtr.pointee=display as NSString;selection?.pointee=NSRange(location:offset,length:0)
        return false
    }
}
