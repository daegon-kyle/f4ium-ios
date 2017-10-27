//
//  StepCollectionViewItem.m
//  SonOfGrab
//
//  Created by Mobile_KFTC on 2017. 9. 8..
//
//

#import "StepCollectionViewItem.h"

@interface StepCollectionViewItem ()

@end

@implementation StepCollectionViewItem
@synthesize txtTitle, imgView, radioCoordinate, radioID, tfCmdCooridatenate, tfCmdID, tfComment;
@synthesize btnMoveUp, btnMoveDown, btnAddEvent, btnRemoveEvent;

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view setWantsLayer:YES];
    [self.view.layer setBackgroundColor:[NSColor colorWithRed:211.0/255 green:212.0/255 blue:213.0/255 alpha:0.33].CGColor];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    
    if (representedObject != nil) {
        [txtTitle setStringValue:[NSString stringWithFormat:@"Step #%@", [representedObject valueForKey:@"cmdNumber"]]];
        [imgView setImage:[representedObject valueForKey:@"image"]];
        [tfCmdCooridatenate setStringValue:[representedObject valueForKey:@"cmdCoordinate"]];
        [tfCmdID setStringValue:[representedObject valueForKey:@"cmdID"]];
        [btnMoveUp setTag:[[representedObject valueForKey:@"cmdNumber"] integerValue]];
        [btnMoveDown setTag:[[representedObject valueForKey:@"cmdNumber"] integerValue]];
        [btnAddEvent setTag:[[representedObject valueForKey:@"cmdNumber"] integerValue]];
        [btnRemoveEvent setTag:[[representedObject valueForKey:@"cmdNumber"] integerValue]];
        
        if ([representedObject valueForKey:@"comment"] != nil)
            [tfComment setStringValue:[representedObject valueForKey:@"commment"]];
        
        if (tfCmdID.stringValue.length == 0)
            [self clickRadioCoordinate:nil];
        else
            [self clickRadioID:nil];
    }
}

- (IBAction)clickRadioCoordinate:(id)sender {
    [radioCoordinate setState:NSOnState];
    [radioID setState:NSOffState];
}

- (IBAction)clickRadioID:(id)sender {
    [radioCoordinate setState:NSOffState];
    [radioID setState:NSOnState];
}

@end
